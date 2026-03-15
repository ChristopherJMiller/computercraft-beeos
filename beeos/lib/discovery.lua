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

--- Get the export chest name with backwards-compatible fallback.
-- @param config BeeOS config
-- @return Peripheral name or nil
local function getExportChest(config)
  return config.chests.export
    or config.chests.productOutput
    or config.chests.surplusOutput
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
  local supplyChest = config.chests.supplyInput
  if not supplyChest then
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

  local supplyPeri = peripheral.wrap(supplyChest)
  if not supplyPeri then return false end
  local supplySize = supplyPeri.size and supplyPeri.size() or 0

  -- Find rocky princess
  local princessSlot = nil
  for slot = 1, supplySize do
    local meta = supplyPeri.getItemMeta and supplyPeri.getItemMeta(slot)
    if meta and (meta.name or ""):find("bee_princess") then
      local info = bee.inspect(supplyPeri, slot)
      -- Rocky bees or any available princess
      if info then
        princessSlot = slot
        break
      end
    end
  end

  -- Find rocky drone
  local droneSlot = nil
  for slot = 1, supplySize do
    local meta = supplyPeri.getItemMeta and supplyPeri.getItemMeta(slot)
    if meta and (meta.name or ""):find("bee_drone") then
      droneSlot = slot
      break
    end
  end

  if not princessSlot or not droneSlot then
    tracker.addLog("Discovery: need rocky princess + drone in supply chest")
    discovery.state = "idle"
    return false
  end

  -- Find template for parent1 (for the princess)
  local sampleStorage = config.chests.sampleStorage
  local template1Slot = discovery.findTemplate(supplyChest, supplyPeri, supplySize, mut.parent1)
  if not template1Slot and sampleStorage then
    local storagePeri = peripheral.wrap(sampleStorage)
    if storagePeri then
      template1Slot = discovery.findTemplate(sampleStorage, storagePeri,
        storagePeri.size and storagePeri.size() or 0, mut.parent1)
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
  local exportChest = getExportChest(config)

  -- Check output slots for results
  for slot = 1, size do
    local meta = mutatronPeri.getItemMeta and mutatronPeri.getItemMeta(slot)
    if meta then
      local itemName = meta.name or ""

      -- Handle genetic waste from mutatron
      if itemName:find("waste") then
        if exportChest then
          inventory.move(mutatronName, slot, exportChest)
          tracker.addLog("Mutatron: genetic waste -> export")
        end

      elseif meta.individual then
        local info = bee.inspect(mutatronPeri, slot)
        if info then
          local droneBuffer = config.chests.droneBuffer

          if info.species == discovery.currentTarget then
            -- Success! Found our target species
            tracker.addLog("SUCCESS: Bred " .. info.species .. "!")
            discovery.markDiscovered(info.species)

            -- Move to drone buffer for sampling
            if droneBuffer then
              inventory.move(mutatronName, slot, droneBuffer)
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
            if droneBuffer then
              inventory.move(mutatronName, slot, droneBuffer)
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
