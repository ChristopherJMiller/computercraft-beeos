-- BeeOS Layer 3: Auto-Discovery
-- Autonomously discovers new bee species by traversing the mutation tree.
-- Uses the basic Mutatron + Genetic Imprinter to create parent bees,
-- then mutates them to produce new species.

local bee = require("lib.bee")
local inventory = require("lib.inventory")
local mutations = require("lib.mutations")
local tracker = require("lib.tracker")
local state = require("lib.state")

local discovery = {}

-- Current discovery state
discovery.state = "idle"  -- idle, imprinting, mutating, inspecting
discovery.currentTarget = nil
discovery.currentMutation = nil
discovery.attempts = 0
discovery.maxAttempts = 10  -- max retries per target before moving on
discovery.discovered = {}   -- { [species] = true } set of known species

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
    config.discovery.prioritySpecies
  )
end

--- Run one cycle of the discovery process.
-- @param machines Table from network.scan()
-- @param config BeeOS config
-- @return boolean true if progress was made
function discovery.tick(machines, config)
  if discovery.state == "idle" then
    return discovery.startNext(machines, config)
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
    discovery.state = "idle"
    return false
  end

  discovery.currentTarget = target
  discovery.currentMutation = mutation
  discovery.attempts = 0
  discovery.state = "imprinting"

  tracker.addLog("Discovery target: " .. target ..
    " (" .. mutation.parent1 .. " + " .. mutation.parent2 .. ")")

  -- Start imprinting parent bees
  return discovery.startImprinting(machines, config)
end

--- Imprint rocky bees as the parent species.
-- Need to imprint a princess as parent1 and a drone as parent2 (or vice versa).
function discovery.startImprinting(machines, config)
  local mut = discovery.currentMutation
  if not mut then return false end

  -- Find imprinter
  local imprinterName
  if config.machines.imprinters then
    imprinterName = config.machines.imprinters[1]
  else
    imprinterName = next(machines.imprinter or {})
  end

  if not imprinterName then
    tracker.addLog("Discovery: no imprinter found!")
    discovery.state = "idle"
    return false
  end

  -- We need:
  -- 1. Rocky princess → imprint as parent1
  -- 2. Rocky drone → imprint as parent2
  -- 3. Templates for parent1 and parent2
  -- 4. Labware for each imprint operation

  -- For now, we just check if the parent templates exist and rocky bees are available.
  -- The actual imprinting process is multi-step and needs the imprinter to be free.

  -- Check if we have templates for both parents
  if not inventory.first(config.chests.supplyInput) then
    tracker.addLog("Discovery: no supply chest configured!")
    discovery.state = "idle"
    return false
  end

  -- Queue the imprinting: parent1 princess, parent2 drone
  -- This is a simplified version — full implementation would:
  -- 1. Find or request rocky princess from AE2
  -- 2. Find template for parent1
  -- 3. Put both + labware in imprinter
  -- 4. Wait for result
  -- 5. Move imprinted princess to mutatron staging
  -- 6. Repeat for drone with parent2 template

  -- For the MVP, we assume templates and rocky bees are in the supply chest.
  -- Push princess + template + labware to imprinter.

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
    tracker.addLog("Discovery: need rocky princess + drone in supply chest")
    discovery.state = "idle"
    return false
  end

  -- Find template for parent1 across supplyInput + sampleStorage
  local templateChests = {}
  for _, n in ipairs(inventory.normalize(config.chests.supplyInput)) do
    templateChests[#templateChests + 1] = n
  end
  for _, n in ipairs(inventory.normalize(config.chests.sampleStorage)) do
    templateChests[#templateChests + 1] = n
  end

  local template1Slot = nil
  for _, chestName in ipairs(templateChests) do
    local p = peripheral.wrap(chestName)
    if p then
      template1Slot = discovery.findTemplate(chestName, p,
        p.size and p.size() or 0, mut.parent1)
      if template1Slot then break end
    end
  end

  if not template1Slot then
    tracker.addLog("Discovery: no template for " .. mut.parent1)
    discovery.state = "idle"
    return false
  end

  -- TODO: Full imprinting sequence
  -- For MVP, move items to imprinter and track state
  -- The actual slot assignments in the imprinter need Phase 0 verification

  tracker.addLog("Imprinting princess as " .. mut.parent1 .. "...")
  discovery.state = "imprinting"
  return true
end

--- Find a genetic template for a species in a given inventory.
-- @return slot number or nil
function discovery.findTemplate(periName, peri, size, species)
  for slot = 1, size do
    local meta = peri.getItemMeta and peri.getItemMeta(slot)
    if meta and (meta.name or ""):find("gene_template") then
      if (meta.displayName or ""):find(species) then
        return slot
      end
    end
  end
  return nil
end

--- Check if imprinting is complete and move to mutation.
function discovery.checkImprinting(machines, config)
  -- Check imprinter output for imprinted bees
  -- When both parent princess and drone are ready, move to mutatron
  -- This needs Phase 0 verification of imprinter slot layout

  -- For now, transition to mutating state
  -- Full implementation tracks the two-step imprint process
  discovery.state = "mutating"
  return discovery.startMutation(machines, config)
end

--- Start a mutation in the basic Mutatron.
function discovery.startMutation(machines, config)
  local mutatronName
  if config.machines.mutatrons then
    mutatronName = config.machines.mutatrons[1]
  else
    mutatronName = next(machines.mutatron or {})
  end

  if not mutatronName then
    tracker.addLog("Discovery: no mutatron found!")
    discovery.state = "idle"
    return false
  end

  -- Push imprinted princess + drone + labware + mutagen to mutatron
  -- Slot layout needs Phase 0 verification
  -- Basic Mutatron: princess in, drone in, labware in, mutagen tank
  -- Result: mutated princess/queen in output

  discovery.state = "mutating"
  discovery.attempts = discovery.attempts + 1

  tracker.addLog("Mutating: attempt " .. discovery.attempts ..
    " for " .. (discovery.currentTarget or "?"))
  return true
end

--- Check the Mutatron output and inspect the result.
function discovery.checkMutatron(machines, config)
  local mutatronName
  if config.machines.mutatrons then
    mutatronName = config.machines.mutatrons[1]
  else
    mutatronName = next(machines.mutatron or {})
  end

  if not mutatronName then return false end

  local mutatronPeri = peripheral.wrap(mutatronName)
  if not mutatronPeri then return false end

  local size = mutatronPeri.size and mutatronPeri.size() or 0
  local exportChests = inventory.getExportChests(config)

  -- Check output slots for results
  for slot = 1, size do
    local meta = mutatronPeri.getItemMeta and mutatronPeri.getItemMeta(slot)
    if meta then
      local itemName = meta.name or ""

      -- Handle genetic waste from mutatron
      if itemName:find("waste") then
        if inventory.first(exportChests) then
          inventory.moveTo(mutatronName, slot, exportChests)
          tracker.addLog("Mutatron: genetic waste -> export")
        end

      elseif meta.individual then
        local info = bee.inspect(mutatronPeri, slot)
        if info then
          if info.species == discovery.currentTarget then
            -- Success! Found our target species
            tracker.addLog("SUCCESS: Bred " .. info.species .. "!")
            discovery.markDiscovered(info.species)

            -- Move to drone buffer for sampling
            if inventory.first(config.chests.droneBuffer) then
              inventory.moveTo(mutatronName, slot, config.chests.droneBuffer)
            end

            discovery.state = "idle"
            discovery.currentTarget = nil
            return true

          else
            -- Got a different species (random mutation)
            -- Still potentially useful!
            if not discovery.discovered[info.species] then
              tracker.addLog("Bonus discovery: " .. info.species .. " (wanted " ..
                (discovery.currentTarget or "?") .. ")")
              discovery.markDiscovered(info.species)
            end

            -- Move to buffer for sampling
            if inventory.first(config.chests.droneBuffer) then
              inventory.moveTo(mutatronName, slot, config.chests.droneBuffer)
            end

            -- Retry if we haven't exceeded max attempts
            if discovery.attempts < discovery.maxAttempts then
              discovery.state = "imprinting"
              return true
            else
              tracker.addLog("Max attempts reached for " ..
                (discovery.currentTarget or "?") .. ", moving on")
              discovery.state = "idle"
              discovery.currentTarget = nil
              return false
            end
          end
        end
      end
    end
  end

  return false  -- No output yet, still processing
end

--- Get discovery progress for display.
-- @return Table with progress info
function discovery.getProgress()
  local discovered, total, reachable = mutations.getCounts(discovery.discovered)
  return {
    discovered = discovered,
    total = total,
    reachable = reachable,
    currentTarget = discovery.currentTarget,
    currentMutation = discovery.currentMutation,
    attempts = discovery.attempts,
    state = discovery.state,
  }
end

return discovery
