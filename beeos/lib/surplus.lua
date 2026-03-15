-- BeeOS Surplus Manager
-- Routes excess drones to the DNA Extractor to keep stock lean.

local bee = require("lib.bee")
local inventory = require("lib.inventory")
local tracker = require("lib.tracker")

local surplus = {}

--- Process surplus drones from the drone buffer.
-- Drones above the max threshold get sent to the DNA Extractor (via export chest).
-- @param machines Table from network.scan()
-- @param config BeeOS config
function surplus.process(machines, config)
  local exportChests = inventory.getExportChests(config)
  if not inventory.first(config.chests.droneBuffer) then return end
  if not inventory.first(exportChests) then return end

  local maxDrones = config.thresholds.maxDronesPerSpecies

  -- Count drones per species across all drone buffers
  local droneCounts = {}
  -- droneSlots: { [species] = { {slot, source}, ... } }
  local droneSlots = {}

  local allDrones = inventory.findAcross(config.chests.droneBuffer, function(meta)
    return (meta.name or ""):find("bee_drone") ~= nil
  end)

  for _, match in ipairs(allDrones) do
    local bufPeri = peripheral.wrap(match.source)
    if bufPeri and bee.isDrone(bufPeri, match.slot) then
      local info = bee.inspect(bufPeri, match.slot)
      if info and info.species then
        droneCounts[info.species] = (droneCounts[info.species] or 0) + (info.count or 1)
        if not droneSlots[info.species] then
          droneSlots[info.species] = {}
        end
        local ds = droneSlots[info.species]
        ds[#ds + 1] = { slot = match.slot, source = match.source, count = info.count or 1 }
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
        local toMove = math.min(excess, slots[i].count)
        local moved = inventory.moveTo(slots[i].source, slots[i].slot, exportChests, nil, toMove)
        excess = excess - moved
        if moved > 0 then
          tracker.addLog("Surplus " .. species .. ": " .. moved .. " -> export")
        end
      end
    end
  end
end

--- Feed the DNA Extractor from the surplus/export chest.
-- @param machines Table from network.scan()
-- @param config BeeOS config
function surplus.feedExtractor(machines, config)
  local exportChests = inventory.getExportChests(config)
  if not inventory.first(exportChests) then return end

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

  -- Find drones across all export chests
  local drones = inventory.findAcross(exportChests, function(meta)
    return (meta.name or ""):find("bee_drone") ~= nil
  end)

  for _, match in ipairs(drones) do
    -- Send to first extractor with space
    for extractorName in pairs(extractors) do
      local moved = inventory.move(match.source, match.slot, extractorName, nil, 1)
      if moved > 0 then break end
    end
  end
end

return surplus
