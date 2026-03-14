-- BeeOS Layer 1: Apiary Manager
-- Monitors Industrial Apiaries, auto-restarts them, routes output.

local bee = require("lib.bee")
local inventory = require("lib.inventory")
local tracker = require("lib.tracker")

local apiary = {}

-- Apiary status tracking
apiary.status = {}
-- { [name] = { species, state, lastCheck, products } }

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
-- Routes products to AE2, drones to buffer, princesses back or to storage.
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
        -- Princess/queen goes back to this apiary's input or to drone buffer
        -- For now, send to drone buffer for inspection and re-routing
        if config.chests.droneBuffer then
          inventory.move(name, slot, config.chests.droneBuffer)
        end

      elseif itemName:find("bee_drone") then
        -- Drones go to processing buffer
        if config.chests.droneBuffer then
          inventory.move(name, slot, config.chests.droneBuffer)
        end

      else
        -- Products (honeycombs, etc.) go to AE2
        if config.chests.productOutput then
          inventory.move(name, slot, config.chests.productOutput)
        end
      end
    end
  end
end

--- Try to restart an apiary with a princess and drone.
-- First checks the drone buffer for matching bees, then supply chest.
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

  local bufferPeri = peripheral.wrap(droneBuffer)
  if not bufferPeri then return false end

  local bufferSize = bufferPeri.size and bufferPeri.size() or 0

  -- Find a princess in the buffer
  local princessSlot = nil
  for slot = 1, bufferSize do
    if bee.isPrincess(bufferPeri, slot) then
      if targetSpecies then
        local info = bee.inspect(bufferPeri, slot)
        if info and info.species == targetSpecies then
          princessSlot = slot
          break
        end
      else
        princessSlot = slot
        break
      end
    end
  end

  if not princessSlot then return false end

  -- Find a matching drone
  local droneSlot = nil
  local princessInfo = bee.inspect(bufferPeri, princessSlot)
  local wantSpecies = targetSpecies or (princessInfo and princessInfo.species)

  for slot = 1, bufferSize do
    if slot ~= princessSlot and bee.isDrone(bufferPeri, slot) then
      if wantSpecies then
        local info = bee.inspect(bufferPeri, slot)
        if info and info.species == wantSpecies then
          droneSlot = slot
          break
        end
      else
        droneSlot = slot
        break
      end
    end
  end

  if not droneSlot then return false end

  -- Move princess to slot 1, drone to slot 2 of the apiary
  -- (Slot numbers may need adjustment after Phase 0 testing)
  local movedPrincess = inventory.move(droneBuffer, princessSlot, name, 1)
  if movedPrincess > 0 then
    -- Need to re-find drone slot in case items shifted
    -- (pushItems shouldn't shift other slots, but be safe)
    local movedDrone = inventory.move(droneBuffer, droneSlot, name, 2)
    if movedDrone > 0 then
      return true
    end
  end

  return false
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
