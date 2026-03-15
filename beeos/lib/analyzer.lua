-- BeeOS Bee Analyzer
-- Routes unanalyzed bees through the Forestry Analyzer so their
-- genome data is readable for trait checking and imprinting.

local bee = require("lib.bee")
local inventory = require("lib.inventory")
local tracker = require("lib.tracker")

local analyzer = {}

--- Check if a bee needs analysis.
-- @param beeInfo Table returned by bee.inspect()
-- @return boolean
function analyzer.needsAnalysis(beeInfo)
  if not beeInfo then return false end
  return beeInfo.analyzed == false
end

--- Run one analyzer cycle: collect output, load new bees.
-- @param machines Table from network.scan()
-- @param config BeeOS config
function analyzer.tick(machines, config)
  -- Find an analyzer
  local analyzerName
  if config.machines.analyzer then
    analyzerName = config.machines.analyzer
  else
    analyzerName = next(machines.analyzer or {})
  end

  if not analyzerName then return end

  local anl = peripheral.wrap(analyzerName)
  if not anl then return end

  local size = anl.size and anl.size() or 0
  local hasBeeInside = false

  -- Check all slots for output
  for slot = 1, size do
    local meta = anl.getItemMeta and anl.getItemMeta(slot)
    if meta then
      local itemName = meta.name or ""

      if itemName:find("bee_") then
        -- Check if this bee is now analyzed
        local info = bee.inspect(anl, slot)
        if info and info.analyzed ~= false then
          -- Analyzed — route to correct buffer
          local isPrincess = itemName:find("bee_princess") or itemName:find("bee_queen")
          local dest = isPrincess and config.chests.princessStorage or config.chests.droneBuffer

          if inventory.first(dest) then
            local moved = inventory.moveTo(analyzerName, slot, dest)
            if moved > 0 then
              tracker.addLog("Analyzed: " .. (info.species or "?") ..
                " " .. (info.type or "bee"))
            end
          end
        else
          -- Still analyzing (or unanalyzed bee stuck in output)
          hasBeeInside = true
        end
      end
    end
  end

  -- Don't load a new bee if one is still inside
  if hasBeeInside then return end

  -- Scan droneBuffer + princessStorage for unanalyzed bees
  local searchChests = {}
  for _, n in ipairs(inventory.normalize(config.chests.droneBuffer)) do
    searchChests[#searchChests + 1] = n
  end
  for _, n in ipairs(inventory.normalize(config.chests.princessStorage)) do
    searchChests[#searchChests + 1] = n
  end
  if #searchChests == 0 then return end

  local beeMatches = inventory.findAcross(searchChests, function(meta)
    return (meta.name or ""):find("bee_") ~= nil
  end)

  for _, match in ipairs(beeMatches) do
    local bufPeri = peripheral.wrap(match.source)
    if bufPeri then
      local info = bee.inspect(bufPeri, match.slot)
      if info and analyzer.needsAnalysis(info) then
        local moved = inventory.move(match.source, match.slot, analyzerName)
        if moved > 0 then
          tracker.addLog("Analyzing: " .. (info.species or "?") ..
            " " .. (info.type or "bee"))
        end
        -- Only load one bee per tick
        return
      end
    end
  end
end

return analyzer
