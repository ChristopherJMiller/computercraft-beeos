-- BeeOS Layer 1: Apiary Manager
-- Monitors Industrial Apiaries, auto-restarts them, routes output.

local bee = require("lib.bee")
local inventory = require("lib.inventory")
local tracker = require("lib.tracker")
local imprinter = require("lib.imprinter")

local apiary = {}

-- Apiary status tracking
apiary.status = {}
-- { [name] = { species, state, lastCheck, products } }

--- Get the export chest name with backwards-compatible fallback.
-- @param config BeeOS config
-- @return Peripheral name or nil
local function getExportChest(config)
  return config.chests.export
    or config.chests.productOutput
    or config.chests.surplusOutput
end

--- Check a single apiary and manage it.
-- @param name Peripheral name of the apiary
-- @param p Wrapped peripheral
-- @param config BeeOS config table
-- @return Status table for this apiary
function apiary.check(name, p, config)
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
    -- Queen is alive, apiary is running
    local species = "Unknown"
    if queen.individual and queen.individual.genome then
      species = queen.individual.genome.active.species.displayName or "Unknown"
    end
    status.species = species
    status.state = "running"
  else
    -- No queen — apiary needs attention
    status.state = "idle"

    -- Extract all output items
    apiary.extractOutput(name, p, config)

    -- Try to restart with available princess + drone
    local restarted = apiary.tryRestart(name, p, config)
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

  local exportChest = getExportChest(config)

  for slot = outputStart, size do
    local meta = p.getItemMeta and p.getItemMeta(slot)
    if meta then
      local itemName = meta.name or ""

      if itemName:find("bee_princess") or itemName:find("bee_queen") then
        -- Princess → princessStorage if available, else droneBuffer
        local dest = config.chests.princessStorage or config.chests.droneBuffer
        if dest then
          inventory.move(name, slot, dest)
        end

      elseif itemName:find("bee_drone") then
        -- Drones go to processing buffer
        if config.chests.droneBuffer then
          inventory.move(name, slot, config.chests.droneBuffer)
        end

      else
        -- Products (honeycombs, etc.) go to export chest
        if exportChest then
          inventory.move(name, slot, exportChest)
        end
      end
    end
  end
end

--- Try to restart an apiary with a princess and drone.
-- Checks princessStorage first, then droneBuffer for princesses.
-- Bees are checked for required traits before entering the apiary.
-- @param name Peripheral name
-- @param p Wrapped peripheral
-- @param config BeeOS config
-- @return boolean True if successfully restarted
function apiary.tryRestart(name, p, config)
  -- Check what species this apiary should breed
  local targetSpecies = nil
  if config.apiaryAssignments then
    targetSpecies = config.apiaryAssignments[name]
  end

  local droneBuffer = config.chests.droneBuffer
  if not droneBuffer then return false end

  -- Search for a princess: check princessStorage first, then droneBuffer
  local princessSlot, princessSource = apiary.findPrincess(config, targetSpecies)
  if not princessSlot then return false end

  -- Check princess traits — if missing, route to imprinter instead
  local sourcePeri = peripheral.wrap(princessSource)
  if not sourcePeri then return false end

  local princessInfo = bee.inspect(sourcePeri, princessSlot)
  if princessInfo and imprinter.needsImprinting(princessInfo, config) then
    -- Move to drone buffer for imprinter pickup (if not already there)
    if princessSource ~= droneBuffer then
      inventory.move(princessSource, princessSlot, droneBuffer)
    end
    tracker.addLog("Princess " .. (princessInfo.species or "?") ..
      " needs traits, routing to imprinter")
    return false
  end

  -- Find a matching drone in drone buffer
  local bufferPeri = peripheral.wrap(droneBuffer)
  if not bufferPeri then return false end
  local bufferSize = bufferPeri.size and bufferPeri.size() or 0

  local wantSpecies = targetSpecies or (princessInfo and princessInfo.species)

  local droneSlot = nil
  for slot = 1, bufferSize do
    if bee.isDrone(bufferPeri, slot) then
      if wantSpecies then
        local info = bee.inspect(bufferPeri, slot)
        if info and info.species == wantSpecies then
          -- Check drone traits too
          if not imprinter.needsImprinting(info, config) then
            droneSlot = slot
            break
          end
        end
      else
        local info = bee.inspect(bufferPeri, slot)
        if info and not imprinter.needsImprinting(info, config) then
          droneSlot = slot
          break
        end
      end
    end
  end

  if not droneSlot then return false end

  -- Move princess to slot 1, drone to slot 2 of the apiary
  -- (Slot numbers may need adjustment after Phase 0 testing)
  local movedPrincess = inventory.move(princessSource, princessSlot, name, 1)
  if movedPrincess > 0 then
    local movedDrone = inventory.move(droneBuffer, droneSlot, name, 2)
    if movedDrone > 0 then
      return true
    end
  end

  return false
end

--- Find a princess in princessStorage or droneBuffer.
-- @param config BeeOS config
-- @param targetSpecies Optional species filter
-- @return slot, sourceName or nil, nil
function apiary.findPrincess(config, targetSpecies)
  -- Check princessStorage first
  local sources = {}
  if config.chests.princessStorage then
    sources[#sources + 1] = config.chests.princessStorage
  end
  if config.chests.droneBuffer then
    sources[#sources + 1] = config.chests.droneBuffer
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
