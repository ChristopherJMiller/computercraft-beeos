-- BeeOS Surplus Manager
-- Routes excess drones to the DNA Extractor to keep stock lean.

local bee = require("lib.bee")
local inventory = require("lib.inventory")
local tracker = require("lib.tracker")

local surplus = {}

--- Process surplus drones from the drone buffer.
-- Drones above the max threshold get sent to the DNA Extractor (via surplus chest).
-- @param machines Table from network.scan()
-- @param config BeeOS config
function surplus.process(machines, config)
  local droneBuffer = config.chests.droneBuffer
  local surplusOutput = config.chests.surplusOutput
  if not droneBuffer or not surplusOutput then return end

  local bufferPeri = peripheral.wrap(droneBuffer)
  if not bufferPeri then return end

  local maxDrones = config.thresholds.maxDronesPerSpecies
  local bufferSize = bufferPeri.size and bufferPeri.size() or 0

  -- Count drones per species in buffer
  local droneCounts = {}
  local droneSlots = {}  -- { [species] = { slot1, slot2, ... } }

  for slot = 1, bufferSize do
    if bee.isDrone(bufferPeri, slot) then
      local info = bee.inspect(bufferPeri, slot)
      if info and info.species then
        droneCounts[info.species] = (droneCounts[info.species] or 0) + (info.count or 1)
        if not droneSlots[info.species] then
          droneSlots[info.species] = {}
        end
        droneSlots[info.species][#droneSlots[info.species] + 1] = slot
      end
    end
  end

  -- Route surplus
  for species, count in pairs(droneCounts) do
    if count > maxDrones then
      local excess = count - maxDrones
      local slots = droneSlots[species]

      -- Move excess drones to surplus output (DNA Extractor)
      for i = #slots, 1, -1 do
        if excess <= 0 then break end
        local meta = bufferPeri.getItemMeta and bufferPeri.getItemMeta(slots[i])
        if meta then
          local toMove = math.min(excess, meta.count or 1)
          local moved = inventory.move(droneBuffer, slots[i], surplusOutput, nil, toMove)
          excess = excess - moved
          if moved > 0 then
            tracker.addLog("Surplus " .. species .. ": " .. moved .. " -> DNA Extractor")
          end
        end
      end
    end
  end
end

--- Feed the DNA Extractor from the surplus chest.
-- @param machines Table from network.scan()
-- @param config BeeOS config
function surplus.feedExtractor(machines, config)
  local surplusOutput = config.chests.surplusOutput
  if not surplusOutput then return end

  -- Find DNA Extractors
  local extractors = {}
  if config.machines.dnaExtractors then
    for _, name in ipairs(config.machines.dnaExtractors) do
      extractors[name] = peripheral.wrap(name)
    end
  else
    extractors = machines.dnaExtractor or {}
  end

  if not next(extractors) then return end

  local surplusPeri = peripheral.wrap(surplusOutput)
  if not surplusPeri then return end
  local surplusSize = surplusPeri.size and surplusPeri.size() or 0

  for slot = 1, surplusSize do
    local meta = surplusPeri.getItemMeta and surplusPeri.getItemMeta(slot)
    if meta then
      -- Send to first extractor with space
      for extractorName in pairs(extractors) do
        local moved = inventory.move(surplusOutput, slot, extractorName, nil, 1)
        if moved > 0 then break end
      end
    end
  end
end

return surplus
