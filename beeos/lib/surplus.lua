-- BeeOS Surplus Manager
-- Routes excess drones to the DNA Extractor to keep stock lean.

local bee = require("lib.bee")
local inventory = require("lib.inventory")
local tracker = require("lib.tracker")

local surplus = {}

--- Get the export chest name with backwards-compatible fallback.
-- @param config BeeOS config
-- @return Peripheral name or nil
local function getExportChest(config)
  return config.chests.export
    or config.chests.productOutput
    or config.chests.surplusOutput
end

--- Process surplus drones from the drone buffer.
-- Drones above the max threshold get sent to the DNA Extractor (via export chest).
-- @param machines Table from network.scan()
-- @param config BeeOS config
function surplus.process(machines, config)
  local droneBuffer = config.chests.droneBuffer
  local exportChest = getExportChest(config)
  if not droneBuffer or not exportChest then return end

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

      -- Move excess drones to export chest (DNA Extractor picks up from AE2)
      for i = #slots, 1, -1 do
        if excess <= 0 then break end
        local meta = bufferPeri.getItemMeta and bufferPeri.getItemMeta(slots[i])
        if meta then
          local toMove = math.min(excess, meta.count or 1)
          local moved = inventory.move(droneBuffer, slots[i], exportChest, nil, toMove)
          excess = excess - moved
          if moved > 0 then
            tracker.addLog("Surplus " .. species .. ": " .. moved .. " -> export")
          end
        end
      end
    end
  end
end

--- Feed the DNA Extractor from the surplus/export chest.
-- @param machines Table from network.scan()
-- @param config BeeOS config
function surplus.feedExtractor(machines, config)
  local exportChest = getExportChest(config)
  if not exportChest then return end

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

  local exportPeri = peripheral.wrap(exportChest)
  if not exportPeri then return end
  local exportSize = exportPeri.size and exportPeri.size() or 0

  for slot = 1, exportSize do
    local meta = exportPeri.getItemMeta and exportPeri.getItemMeta(slot)
    if meta then
      -- Only feed bees to the extractor, not combs or waste
      local itemName = meta.name or ""
      if itemName:find("bee_drone") then
        -- Send to first extractor with space
        for extractorName in pairs(extractors) do
          local moved = inventory.move(exportChest, slot, extractorName, nil, 1)
          if moved > 0 then break end
        end
      end
    end
  end
end

return surplus
