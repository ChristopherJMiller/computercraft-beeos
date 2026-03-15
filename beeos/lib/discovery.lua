-- BeeOS Layer 3: Auto-Discovery
-- Autonomously discovers new bee species by traversing the mutation tree.
-- Uses the basic Mutatron + Genetic Imprinter to create parent bees,
-- then mutates them to produce new species.

local bee = require("lib.bee")
local inventory = require("lib.inventory")
local mutations = require("lib.mutations")
local tracker = require("lib.tracker")
local state = require("lib.state")

-- Bootstrap queue: species that need establishment (samples + templates)
-- Persisted via state module as "bootstrap_queue" = { [species] = true }

local discovery = {}

-- Gendustry Genetic Imprinter slot indices (0-indexed for CC pushItems)
local IMP_TEMPLATE = 1   -- slot 0: gene template
local IMP_LABWARE = 2    -- slot 1: labware
local IMP_BEE = 3        -- slot 2: bee to imprint
local IMP_OUTPUT = 4     -- slot 3: imprinted bee output

-- Gendustry Basic Mutatron slot indices (0-indexed for CC pushItems)
local MUT_PARENT1 = 1    -- slot 0: parent bee 1
local MUT_PARENT2 = 2    -- slot 1: parent bee 2
local MUT_OUTPUT = 3     -- slot 2: output
local MUT_LABWARE = 4    -- slot 3: labware

-- Current discovery state
discovery.state = "idle"  -- idle, preparing, imprinting, mutating
discovery.idleReason = nil
discovery.currentTarget = nil
discovery.currentMutation = nil
discovery.attempts = 0
discovery.discovered = {}   -- { [species] = true } set of known species
discovery.imprintStep = nil  -- "princess" or "drone" during imprinting
discovery.stagedPrincess = nil  -- { source=, slot= } imprinted princess waiting
discovery.lastConfig = nil  -- cached config for getProgress()

--- Get the staging chest config (discoveryStaging, fallback to supplyInput).
local function getStagingChests(config)
  return config.chests.discoveryStaging or config.chests.supplyInput
end

--- Set idle state with a reason.
local function goIdle(reason)
  discovery.state = "idle"
  discovery.idleReason = reason
  discovery.imprintStep = nil
end

--- Initialize discovery from tracker catalog and persisted state.
function discovery.init()
  -- Load persisted discovered set
  discovery.discovered = state.load("discovered", {})

  -- Also mark anything in the tracker catalog as discovered
  for species in pairs(tracker.catalog) do
    discovery.discovered[species] = true
  end

  state.save("discovered", discovery.discovered)
end

--- Mark a species as discovered.
function discovery.markDiscovered(species)
  if not discovery.discovered[species] then
    discovery.discovered[species] = true
    state.save("discovered", discovery.discovered)
    tracker.addLog("DISCOVERED: " .. species .. "!")
  end
end

--- Add a species to the bootstrap queue (needs samples + templates).
function discovery.addBootstrap(species)
  local queue = state.load("bootstrap_queue", {})
  if not queue[species] then
    queue[species] = true
    state.save("bootstrap_queue", queue)
    tracker.addLog("Bootstrap queued: " .. species)
  end
end

--- Remove a species from the bootstrap queue (fully established).
function discovery.removeBootstrap(species)
  local queue = state.load("bootstrap_queue", {})
  if queue[species] then
    queue[species] = nil
    state.save("bootstrap_queue", queue)
    tracker.addLog("Bootstrap complete: " .. species)
  end
end

--- Get the current bootstrap queue.
function discovery.getBootstrapQueue()
  return state.load("bootstrap_queue", {})
end

--- Route a bee from the Mutatron output to the correct storage.
-- Queens/princesses go to princessStorage, drones go to droneBuffer.
-- @param mutatronName Peripheral name of the Mutatron
-- @param info Bee info from bee.inspect()
-- @param config BeeOS config
local function routeMutatronOutput(mutatronName, info, config)
  if info.type == "queen" or info.type == "princess" then
    if inventory.first(config.chests.princessStorage) then
      inventory.moveTo(mutatronName, MUT_OUTPUT, config.chests.princessStorage)
    end
    discovery.addBootstrap(info.species)
  else
    if inventory.first(config.chests.droneBuffer) then
      inventory.moveTo(mutatronName, MUT_OUTPUT, config.chests.droneBuffer)
    end
  end
end

--- Pick the next species to target for discovery.
-- @param config BeeOS config
-- @return species name and mutation step, or nil
function discovery.pickTarget(config)
  local skipSet = {}
  for _, name in ipairs(config.discovery.skipSpecies or {}) do
    skipSet[name] = true
  end

  return mutations.getNextTarget(
    discovery.discovered,
    skipSet,
    config.discovery.prioritySpecies,
    tracker.catalog,
    config.thresholds
  )
end

--- Run one cycle of the discovery process.
-- @param machines Table from network.scan()
-- @param config BeeOS config
-- @return boolean true if progress was made
function discovery.tick(machines, config)
  discovery.lastConfig = config

  if discovery.state == "idle" then
    return discovery.startNext(machines, config)
  elseif discovery.state == "preparing" then
    return discovery.prepare(machines, config)
  elseif discovery.state == "imprinting" then
    return discovery.checkImprinting(machines, config)
  elseif discovery.state == "mutating" then
    return discovery.checkMutatron(machines, config)
  end
  return false
end

--- Start the next discovery target.
function discovery.startNext(machines, config)
  local target, mutation = discovery.pickTarget(config)
  if not target then
    goIdle("No reachable species")
    return false
  end

  discovery.currentTarget = target
  discovery.currentMutation = mutation
  discovery.attempts = 0
  discovery.idleReason = nil
  discovery.stagedPrincess = nil
  discovery.state = "preparing"

  tracker.addLog("Discovery target: " .. target ..
    " (" .. mutation.parent1 .. " + " .. mutation.parent2 .. ")")

  -- Immediately try to prepare
  return discovery.prepare(machines, config)
end

--- Find a genetic template for a species in a given inventory.
-- Uses nbtHash lookup (learned at craft time) to identify template species.
-- @return slot number or nil
function discovery.findTemplate(periName, peri, size, species)
  local sampler = require("lib.sampler")
  for slot = 1, size do
    local meta = peri.getItemMeta and peri.getItemMeta(slot)
    if meta and (meta.name or ""):find("gene_template") then
      local templateSpecies = sampler.lookupTemplateHash(meta.nbtHash)
      if templateSpecies == species then
        return slot
      end
    end
  end
  return nil
end

--- Prepare for imprinting: gather all prerequisites and load the imprinter.
function discovery.prepare(machines, config)
  local mut = discovery.currentMutation
  if not mut then
    goIdle("No mutation selected")
    return false
  end

  -- Find imprinter
  local imprinterName
  if config.machines.imprinters then
    imprinterName = config.machines.imprinters[1]
  else
    imprinterName = next(machines.imprinter or {})
  end

  if not imprinterName then
    goIdle("No imprinter found")
    return false
  end

  -- Check supply chest
  if not inventory.first(config.chests.supplyInput) then
    goIdle("No supply chest")
    return false
  end

  -- Find rocky princess across supply chests
  local princessMatch = nil
  local princessMatches = inventory.findAcross(config.chests.supplyInput, function(meta)
    return (meta.name or ""):find("bee_princess") ~= nil
  end)
  for _, match in ipairs(princessMatches) do
    local p = peripheral.wrap(match.source)
    if p then
      local info = bee.inspect(p, match.slot)
      if info then
        princessMatch = match
        break
      end
    end
  end

  -- Find rocky drone across supply chests
  local droneMatch = nil
  local droneMatches = inventory.findAcross(config.chests.supplyInput, function(meta)
    return (meta.name or ""):find("bee_drone") ~= nil
  end)
  if droneMatches[1] then
    droneMatch = droneMatches[1]
  end

  if not princessMatch or not droneMatch then
    goIdle("Need rocky princess + drone")
    return false
  end

  -- Build template search chests
  local templateChests = {}
  for _, n in ipairs(inventory.normalize(config.chests.supplyInput)) do
    templateChests[#templateChests + 1] = n
  end
  for _, n in ipairs(inventory.normalize(config.chests.sampleStorage)) do
    templateChests[#templateChests + 1] = n
  end
  if config.chests.templateOutput then
    for _, n in ipairs(inventory.normalize(config.chests.templateOutput)) do
      templateChests[#templateChests + 1] = n
    end
  end

  -- Find template for parent1
  local template1Slot, template1Source = nil, nil
  for _, chestName in ipairs(templateChests) do
    local p = peripheral.wrap(chestName)
    if p then
      template1Slot = discovery.findTemplate(chestName, p,
        p.size and p.size() or 0, mut.parent1)
      if template1Slot then
        template1Source = chestName
        break
      end
    end
  end

  if not template1Slot then
    goIdle("No template: " .. mut.parent1)
    return false
  end

  -- Find template for parent2
  local template2Slot, template2Source = nil, nil
  for _, chestName in ipairs(templateChests) do
    local p = peripheral.wrap(chestName)
    if p then
      template2Slot = discovery.findTemplate(chestName, p,
        p.size and p.size() or 0, mut.parent2)
      if template2Slot then
        template2Source = chestName
        break
      end
    end
  end

  if not template2Slot then
    goIdle("No template: " .. mut.parent2)
    return false
  end

  -- Find labware
  local labwareMatches = inventory.findAcross(config.chests.supplyInput, function(m)
    return (m.name or ""):find("labware") ~= nil
  end)
  if not labwareMatches[1] then
    goIdle("No labware")
    return false
  end

  -- All prerequisites met! Load imprinter with princess + parent1 template
  tracker.addLog("Imprinting princess as " .. mut.parent1 .. "...")

  local movedBee = inventory.move(princessMatch.source, princessMatch.slot,
    imprinterName, IMP_BEE)
  if movedBee == 0 then
    goIdle("Failed to load princess")
    return false
  end

  inventory.move(template1Source, template1Slot, imprinterName, IMP_TEMPLATE)
  inventory.move(labwareMatches[1].source, labwareMatches[1].slot,
    imprinterName, IMP_LABWARE)

  -- Store references for drone imprinting later
  discovery.droneMatch = droneMatch
  discovery.template2Source = template2Source
  discovery.template2Slot = template2Slot
  discovery.imprinterName = imprinterName

  discovery.state = "imprinting"
  discovery.imprintStep = "princess"
  discovery.idleReason = nil
  return true
end

--- Check if imprinting is complete and handle output.
function discovery.checkImprinting(machines, config)
  local imprinterName = discovery.imprinterName
  if not imprinterName then
    goIdle("Lost imprinter reference")
    return false
  end

  local imp = peripheral.wrap(imprinterName)
  if not imp then
    goIdle("Imprinter disconnected")
    return false
  end

  -- Check output slot for result
  local meta = imp.getItemMeta and imp.getItemMeta(IMP_OUTPUT)
  if not meta then
    return false  -- Still processing
  end

  local itemName = meta.name or ""

  -- Handle genetic waste (imprint failed)
  if itemName:find("waste") then
    local exportChests = inventory.getExportChests(config)
    if inventory.first(exportChests) then
      inventory.move(imprinterName, IMP_OUTPUT, inventory.first(exportChests))
    end
    tracker.addLog("Imprint failed: genetic waste for " ..
      (discovery.imprintStep or "?"))
    -- Restart preparation
    discovery.state = "preparing"
    discovery.imprintStep = nil
    return true
  end

  -- Handle imprinted bee output
  if itemName:find("bee_") then
    if discovery.imprintStep == "princess" then
      -- Stage imprinted princess in staging chest
      local staged = inventory.moveTo(imprinterName, IMP_OUTPUT,
        getStagingChests(config))
      if staged == 0 then
        goIdle("No space to stage princess")
        return false
      end

      -- Remember where we staged her
      -- Find her in the staging chest (she was just moved there)
      local princessMatches = inventory.findAcross(getStagingChests(config), function(m)
        return (m.name or ""):find("bee_princess") ~= nil
      end)
      -- Pick the last match (most likely the one we just moved)
      if princessMatches[1] then
        discovery.stagedPrincess = {
          source = princessMatches[#princessMatches].source,
          slot = princessMatches[#princessMatches].slot,
        }
      end

      tracker.addLog("Princess imprinted as " ..
        (discovery.currentMutation and discovery.currentMutation.parent1 or "?"))

      -- Now imprint the drone with parent2 template
      local droneMatch = discovery.droneMatch
      local template2Source = discovery.template2Source
      local template2Slot = discovery.template2Slot

      if not droneMatch or not template2Source or not template2Slot then
        goIdle("Lost drone/template references")
        return false
      end

      -- Find fresh labware
      local labwareMatches = inventory.findAcross(config.chests.supplyInput, function(m)
        return (m.name or ""):find("labware") ~= nil
      end)
      if not labwareMatches[1] then
        goIdle("No labware for drone")
        return false
      end

      tracker.addLog("Imprinting drone as " ..
        (discovery.currentMutation and discovery.currentMutation.parent2 or "?") .. "...")

      local movedDrone = inventory.move(droneMatch.source, droneMatch.slot,
        imprinterName, IMP_BEE)
      if movedDrone == 0 then
        goIdle("Failed to load drone")
        return false
      end

      -- Re-find template2 in case it moved (another process may have shifted slots)
      local mut = discovery.currentMutation
      local templateChests = {}
      for _, n in ipairs(inventory.normalize(config.chests.supplyInput)) do
        templateChests[#templateChests + 1] = n
      end
      for _, n in ipairs(inventory.normalize(config.chests.sampleStorage)) do
        templateChests[#templateChests + 1] = n
      end

      local t2Slot, t2Source = nil, nil
      for _, chestName in ipairs(templateChests) do
        local p = peripheral.wrap(chestName)
        if p then
          t2Slot = discovery.findTemplate(chestName, p,
            p.size and p.size() or 0, mut.parent2)
          if t2Slot then
            t2Source = chestName
            break
          end
        end
      end

      if not t2Slot then
        goIdle("No template: " .. mut.parent2)
        return false
      end

      -- Extract template1 before loading template2
      local templateDest = config.chests.templateOutput
      if inventory.first(templateDest) then
        inventory.move(imprinterName, IMP_TEMPLATE,
          inventory.first(templateDest))
      end

      inventory.move(t2Source, t2Slot, imprinterName, IMP_TEMPLATE)
      inventory.move(labwareMatches[1].source, labwareMatches[1].slot,
        imprinterName, IMP_LABWARE)

      discovery.imprintStep = "drone"
      return true

    elseif discovery.imprintStep == "drone" then
      -- Drone imprinted! Extract template before moving on.
      local templateDest = config.chests.templateOutput
      if inventory.first(templateDest) then
        inventory.move(imprinterName, IMP_TEMPLATE,
          inventory.first(templateDest))
      end

      tracker.addLog("Drone imprinted as " ..
        (discovery.currentMutation and discovery.currentMutation.parent2 or "?"))

      return discovery.startMutation(machines, config, imprinterName)
    end
  end

  return false
end

--- Start a mutation in the basic Mutatron.
-- @param imprinterName The imprinter that has the drone in output slot
function discovery.startMutation(machines, config, imprinterName)
  local mutatronName
  if config.machines.mutatrons then
    mutatronName = config.machines.mutatrons[1]
  else
    mutatronName = next(machines.mutatron or {})
  end

  if not mutatronName then
    -- Move drone out of imprinter to staging chest before going idle
    if imprinterName then
      inventory.moveTo(imprinterName, IMP_OUTPUT, getStagingChests(config))
    end
    goIdle("No mutatron found")
    return false
  end

  -- Find labware for the mutatron
  local labwareMatches = inventory.findAcross(config.chests.supplyInput, function(m)
    return (m.name or ""):find("labware") ~= nil
  end)
  if not labwareMatches[1] then
    if imprinterName then
      inventory.moveTo(imprinterName, IMP_OUTPUT, getStagingChests(config))
    end
    goIdle("No labware for mutatron")
    return false
  end

  -- Move imprinted drone from imprinter output to mutatron parent2
  if imprinterName then
    local movedDrone = inventory.move(imprinterName, IMP_OUTPUT,
      mutatronName, MUT_PARENT2)
    if movedDrone == 0 then
      goIdle("Failed to load drone to mutatron")
      return false
    end
  end

  -- Move staged princess to mutatron parent1
  if discovery.stagedPrincess then
    local movedPrincess = inventory.move(
      discovery.stagedPrincess.source, discovery.stagedPrincess.slot,
      mutatronName, MUT_PARENT1)
    if movedPrincess == 0 then
      goIdle("Failed to load princess to mutatron")
      return false
    end
    discovery.stagedPrincess = nil
  else
    goIdle("No staged princess for mutatron")
    return false
  end

  -- Add labware
  inventory.move(labwareMatches[1].source, labwareMatches[1].slot,
    mutatronName, MUT_LABWARE)

  discovery.state = "mutating"
  discovery.imprintStep = nil
  discovery.attempts = discovery.attempts + 1
  discovery.mutatronName = mutatronName

  tracker.addLog("Mutating: attempt " .. discovery.attempts ..
    " for " .. (discovery.currentTarget or "?"))
  return true
end

--- Check the Mutatron output and inspect the result.
function discovery.checkMutatron(machines, config)
  local mutatronName = discovery.mutatronName
  if not mutatronName then
    if config.machines.mutatrons then
      mutatronName = config.machines.mutatrons[1]
    else
      mutatronName = next(machines.mutatron or {})
    end
  end

  if not mutatronName then
    goIdle("Mutatron disconnected")
    return false
  end

  local mutatronPeri = peripheral.wrap(mutatronName)
  if not mutatronPeri then
    goIdle("Mutatron disconnected")
    return false
  end

  -- Check output slot for result
  local meta = mutatronPeri.getItemMeta and mutatronPeri.getItemMeta(MUT_OUTPUT)
  if not meta then
    return false  -- Still processing
  end

  local itemName = meta.name or ""
  local exportChests = inventory.getExportChests(config)

  -- Handle genetic waste from mutatron
  if itemName:find("waste") then
    if inventory.first(exportChests) then
      inventory.move(mutatronName, MUT_OUTPUT, inventory.first(exportChests))
      tracker.addLog("Mutatron: genetic waste -> export")
    end
    -- Retry
    discovery.state = "preparing"
    return true
  end

  if meta.individual then
    local info = bee.inspect(mutatronPeri, MUT_OUTPUT)
    if info then
      if info.species == discovery.currentTarget then
        -- Success! Found our target species
        tracker.addLog("SUCCESS: Bred " .. info.species .. "!")
        discovery.markDiscovered(info.species)

        -- Route based on bee type (queen/princess -> apiary, drone -> sampling)
        routeMutatronOutput(mutatronName, info, config)

        goIdle(nil)
        discovery.currentTarget = nil
        return true

      else
        -- Got a different species (random mutation)
        if not discovery.discovered[info.species] then
          tracker.addLog("Bonus discovery: " .. info.species .. " (wanted " ..
            (discovery.currentTarget or "?") .. ")")
          discovery.markDiscovered(info.species)
        end

        -- Route based on bee type (queen/princess -> apiary, drone -> sampling)
        routeMutatronOutput(mutatronName, info, config)

        -- Retry — keep going until we get the target
        discovery.state = "preparing"
        return true
      end
    end
  end

  -- Unknown item in output — move to export
  if inventory.first(exportChests) then
    inventory.move(mutatronName, MUT_OUTPUT, inventory.first(exportChests))
  end

  return false
end

--- Get discovery progress for display.
-- @return Table with progress info
function discovery.getProgress()
  local discovered, total, reachable = mutations.getCounts(discovery.discovered)

  -- Build candidate list if we have config cached
  local candidates = {}
  if discovery.lastConfig then
    local skipSet = {}
    for _, name in ipairs((discovery.lastConfig.discovery or {}).skipSpecies or {}) do
      skipSet[name] = true
    end
    candidates = mutations.getCandidateList(discovery.discovered, skipSet, 5,
      tracker.catalog, (discovery.lastConfig or {}).thresholds)
  end

  return {
    discovered = discovered,
    total = total,
    reachable = reachable,
    currentTarget = discovery.currentTarget,
    currentMutation = discovery.currentMutation,
    attempts = discovery.attempts,
    state = discovery.state,
    idleReason = discovery.idleReason,
    imprintStep = discovery.imprintStep,
    candidates = candidates,
    bootstrapQueue = discovery.getBootstrapQueue(),
  }
end

return discovery
