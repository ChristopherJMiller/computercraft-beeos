-- BeeOS Layer 1: Apiary Manager
-- Monitors Industrial Apiaries, auto-restarts them, routes output.

local bee = require("lib.bee")
local inventory = require("lib.inventory")
local tracker = require("lib.tracker")
local imprinter = require("lib.imprinter")
local state = require("lib.state")

local apiary = {}

-- Apiary status tracking
apiary.status = {}
-- { [name] = { species, state, lastCheck, products } }

--- Check a single apiary and manage it.
-- @param name Peripheral name of the apiary
-- @param p Wrapped peripheral
-- @param config BeeOS config table
-- @param machines Table from network.scan()
-- @return Status table for this apiary
function apiary.check(name, p, config, machines)
  local status = apiary.status[name] or {
    species = nil,
    state = "unknown",
    lastCheck = 0,
  }

  -- Check for active queen
  local queen = nil
  if p.getQueen then
    queen = p.getQueen()
  end

  if queen then
    local species = "Unknown"
    if queen.individual and queen.individual.genome then
      species = queen.individual.genome.active.species.displayName or "Unknown"
    end
    status.species = species

    -- Check if the queen has required traits; if not, she's stuck
    local queenInfo = bee.inspect(p, 1)
    if queenInfo and imprinter.needsImprinting(queenInfo, config) then
      tracker.addLog("Stuck queen in " .. name .. ": missing traits, extracting")
      apiary.extractInputs(name, p, config)
      status.state = "idle"

      local restarted = apiary.tryRestart(name, p, config, machines)
      if restarted then
        status.state = "restarting"
        tracker.addLog("Restarted apiary: " .. name)
      end
    else
      status.state = "running"
    end
  else
    -- No queen — apiary needs attention
    status.state = "idle"

    -- Extract all output items
    apiary.extractOutput(name, p, config)

    -- Try to restart with available princess + drone
    local restarted = apiary.tryRestart(name, p, config, machines)
    if restarted then
      status.state = "restarting"
      tracker.addLog("Restarted apiary: " .. name)
    end
  end

  status.lastCheck = os.clock()
  apiary.status[name] = status
  return status
end

--- Extract output items from an apiary.
-- Routes products to export, drones to buffer, princesses to princessStorage or buffer.
-- @param name Peripheral name
-- @param p Wrapped peripheral
-- @param config BeeOS config
function apiary.extractOutput(name, p, config)
  local size = p.size and p.size() or 0

  -- Industrial Apiary layout (verify with tools/slots):
  -- Slots 1-2: princess/drone input
  -- Slots 3-6: upgrades
  -- Slots 7+: output
  -- We scan all slots and only extract from output area
  local outputStart = 7  -- Adjust after Phase 0 testing

  for slot = outputStart, size do
    local meta = p.getItemMeta and p.getItemMeta(slot)
    if meta then
      local itemName = meta.name or ""

      if itemName:find("bee_princess") or itemName:find("bee_queen") then
        -- Princess → princessStorage only (don't mix with drone buffer)
        if inventory.first(config.chests.princessStorage) then
          inventory.moveTo(name, slot, config.chests.princessStorage)
        end

      elseif itemName:find("bee_drone") then
        -- Drones go to processing buffer
        if inventory.first(config.chests.droneBuffer) then
          inventory.moveTo(name, slot, config.chests.droneBuffer)
        end

      else
        -- Products (honeycombs, etc.) go to export chest
        local exportChests = inventory.getExportChests(config)
        if inventory.first(exportChests) then
          inventory.moveTo(name, slot, exportChests)
        end
      end
    end
  end
end

--- Extract bees from apiary input slots (for shutdown/recovery).
-- Only extracts from slots 1-2 (princess/queen and drone inputs).
-- Does NOT run during normal operation — only during shutdown.
-- @param name Peripheral name
-- @param p Wrapped peripheral
-- @param config BeeOS config
function apiary.extractInputs(name, p, config)
  for slot = 1, 2 do
    local meta = p.getItemMeta and p.getItemMeta(slot)
    if meta then
      local itemName = meta.name or ""
      if itemName:find("bee_princess") or itemName:find("bee_queen") then
        if inventory.first(config.chests.princessStorage) then
          inventory.moveTo(name, slot, config.chests.princessStorage)
        end
      elseif itemName:find("bee_drone") then
        if inventory.first(config.chests.droneBuffer) then
          inventory.moveTo(name, slot, config.chests.droneBuffer)
        end
      end
    end
  end
end

--- Try to restart an apiary with a princess and drone.
-- Checks princessStorage first, then droneBuffer for princesses.
-- Bees are checked for required traits before entering the apiary;
-- if traits are missing, the bee is routed to the imprinter with the
-- apiary-ready template.
-- @param name Peripheral name
-- @param p Wrapped peripheral
-- @param config BeeOS config
-- @param machines Table from network.scan()
-- @return boolean True if successfully restarted
function apiary.tryRestart(name, p, config, machines)
  -- Check what species this apiary should breed
  local targetSpecies = nil
  if config.apiaryAssignments then
    targetSpecies = config.apiaryAssignments[name]
  end

  -- Check bootstrap queue for priority species (when no assignment set)
  local bootstrapTarget = nil
  if not targetSpecies then
    local queue = state.load("bootstrap_queue", {})
    bootstrapTarget = next(queue)
  end

  -- Try queens first — they go in slot 1 alone, no drone needed.
  -- Always try any queen to break it into princess + drone.
  local queenSpecies = targetSpecies or bootstrapTarget
  local queenSlot, queenSource = apiary.findQueen(config, queenSpecies)
  if not queenSlot then
    queenSlot, queenSource = apiary.findQueen(config, nil)
  end
  if queenSlot then
    -- Check queen traits before placing in apiary (mirrors princess path below)
    local qPeri = peripheral.wrap(queenSource)
    if qPeri then
      local queenInfo = bee.inspect(qPeri, queenSlot)
      if queenInfo and imprinter.needsImprinting(queenInfo, config) then
        imprinter.sendToImprinter(queenSource, queenSlot, machines, config)
        return false
      end
    end

    local movedQueen = inventory.move(queenSource, queenSlot, name, 1)
    if movedQueen > 0 then
      tracker.addLog("Queen placed in apiary: " .. name)
      return true
    end
  end

  -- Fall through to princess+drone logic
  if not inventory.first(config.chests.droneBuffer) then return false end

  local princessSlot, princessSource = apiary.findPrincess(config,
    targetSpecies or bootstrapTarget)
  if not princessSlot then return false end

  -- Check princess traits — if missing, route to imprinter
  local sourcePeri = peripheral.wrap(princessSource)
  if not sourcePeri then return false end

  local princessInfo = bee.inspect(sourcePeri, princessSlot)
  if princessInfo and imprinter.needsImprinting(princessInfo, config) then
    imprinter.sendToImprinter(princessSource, princessSlot, machines, config)
    return false
  end

  -- Find a matching drone across all drone buffers
  local wantSpecies = targetSpecies or (princessInfo and princessInfo.species)

  local droneSlot, droneSource = nil, nil
  local droneMatches = inventory.findAcross(config.chests.droneBuffer, function(meta)
    return (meta.name or ""):find("bee_drone") ~= nil
  end)

  for _, match in ipairs(droneMatches) do
    local bufPeri = peripheral.wrap(match.source)
    if bufPeri and bee.isDrone(bufPeri, match.slot) then
      if wantSpecies then
        local info = bee.inspect(bufPeri, match.slot)
        if info and info.species == wantSpecies then
          if imprinter.needsImprinting(info, config) then
            imprinter.sendToImprinter(match.source, match.slot,
              machines, config)
          else
            droneSlot = match.slot
            droneSource = match.source
            break
          end
        end
      else
        local info = bee.inspect(bufPeri, match.slot)
        if info then
          if imprinter.needsImprinting(info, config) then
            imprinter.sendToImprinter(match.source, match.slot,
              machines, config)
          else
            droneSlot = match.slot
            droneSource = match.source
            break
          end
        end
      end
    end
  end

  if not droneSlot then return false end

  -- Move princess to slot 1, drone to slot 2 of the apiary
  -- (Slot numbers may need adjustment after Phase 0 testing)
  local movedPrincess = inventory.move(princessSource, princessSlot, name, 1)
  if movedPrincess > 0 then
    local movedDrone = inventory.move(droneSource, droneSlot, name, 2)
    if movedDrone > 0 then
      return true
    end
  end

  return false
end

--- Find a princess in princessStorage.
-- @param config BeeOS config
-- @param targetSpecies Optional species filter
-- @return slot, sourceName or nil, nil
function apiary.findPrincess(config, targetSpecies)
  -- Only search princessStorage — princesses should never be in droneBuffer
  local sources = {}
  for _, n in ipairs(inventory.normalize(config.chests.princessStorage)) do
    sources[#sources + 1] = n
  end

  for _, sourceName in ipairs(sources) do
    local peri = peripheral.wrap(sourceName)
    if peri then
      local size = peri.size and peri.size() or 0
      for slot = 1, size do
        if bee.isPrincess(peri, slot) then
          if targetSpecies then
            local info = bee.inspect(peri, slot)
            if info and info.species == targetSpecies then
              return slot, sourceName
            end
          else
            return slot, sourceName
          end
        end
      end
    end
  end

  return nil, nil
end

--- Find a queen in princessStorage.
-- Queens can be placed directly in an apiary without a drone.
-- @param config BeeOS config
-- @param targetSpecies Optional species filter
-- @return slot, sourceName or nil, nil
function apiary.findQueen(config, targetSpecies)
  local sources = inventory.normalize(config.chests.princessStorage)
  for _, sourceName in ipairs(sources) do
    local peri = peripheral.wrap(sourceName)
    if peri then
      local size = peri.size and peri.size() or 0
      for slot = 1, size do
        if bee.isQueen(peri, slot) then
          if targetSpecies then
            local info = bee.inspect(peri, slot)
            if info and info.species == targetSpecies then
              return slot, sourceName
            end
          else
            return slot, sourceName
          end
        end
      end
    end
  end
  return nil, nil
end

--- Get a list of all apiary statuses for display.
-- @return List of { name, species, state }
function apiary.getStatuses()
  local list = {}
  for name, status in pairs(apiary.status) do
    list[#list + 1] = {
      name = name,
      species = status.species or "None",
      state = status.state,
    }
  end
  table.sort(list, function(a, b) return a.name < b.name end)
  return list
end

return apiary
