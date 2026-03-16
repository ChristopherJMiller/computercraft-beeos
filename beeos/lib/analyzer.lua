-- BeeOS Bee Analyzer
-- Routes unanalyzed bees through the Forestry Analyzer so their
-- genome data is readable for trait checking and imprinting.

local bee = require("lib.bee")
local inventory = require("lib.inventory")
local tracker = require("lib.tracker")

local analyzer = {}

-- Activity tracking: { [machineName] = speciesName }
analyzer.activeSpecies = {}

--- Check if a bee needs analysis.
-- @param beeInfo Table returned by bee.inspect()
-- @return boolean
function analyzer.needsAnalysis(beeInfo)
  if not beeInfo then return false end
  return beeInfo.analyzed == false
end

--- Run one analyzer cycle across all available analyzers.
-- @param machines Table from network.scan()
-- @param config BeeOS config
function analyzer.tick(machines, config)
  -- Build list of all analyzers
  local analyzers = {}
  if config.machines.analyzer then
    -- Config uses singular string — wrap into table
    analyzers[config.machines.analyzer] = peripheral.wrap(config.machines.analyzer)
  else
    analyzers = machines.analyzer or {}
  end

  if not next(analyzers) then return end

  -- Phase 1: Collect output from all analyzers, find idle ones
  local idleAnalyzers = {}

  for anlName, anl in pairs(analyzers) do
    if anl then
      local size = anl.size and anl.size() or 0
      local hasBeeInside = false

      for slot = 1, size do
        local meta = anl.getItemMeta and anl.getItemMeta(slot)
        if meta then
          local itemName = meta.name or ""

          if itemName:find("bee_") then
            local info = bee.inspect(anl, slot)
            if info and info.analyzed ~= false then
              local isPrincess = itemName:find("bee_princess") or itemName:find("bee_queen")
              local dest = isPrincess and config.chests.princessStorage or config.chests.droneBuffer

              if inventory.first(dest) then
                local moved = inventory.moveTo(anlName, slot, dest)
                if moved > 0 then
                  tracker.addLog("Analyzed: " .. (info.species or "?") ..
                    " " .. (info.type or "bee"))
                end
              end
            else
              hasBeeInside = true
            end
          end
        end
      end

      if not hasBeeInside then
        idleAnalyzers[#idleAnalyzers + 1] = anlName
        analyzer.activeSpecies[anlName] = nil
      end
    end
  end

  if #idleAnalyzers == 0 then return end

  -- Phase 2: Load bees into idle analyzers
  local searchChests = {}
  for _, n in ipairs(inventory.normalize(config.chests.droneBuffer)) do
    searchChests[#searchChests + 1] = n
  end
  for _, n in ipairs(inventory.normalize(config.chests.princessStorage)) do
    searchChests[#searchChests + 1] = n
  end
  if #searchChests == 0 then return end

  local beeMatches = inventory.findAcross(searchChests, function(m)
    return (m.name or ""):find("bee_") ~= nil
  end)

  local beeIdx = 1
  for _, anlName in ipairs(idleAnalyzers) do
    while beeIdx <= #beeMatches do
      local match = beeMatches[beeIdx]
      beeIdx = beeIdx + 1

      local bufPeri = peripheral.wrap(match.source)
      if bufPeri then
        local info = bee.inspect(bufPeri, match.slot)
        if info and analyzer.needsAnalysis(info)
            and (info.species or ""):lower() ~= "rocky" then
          local moved = inventory.move(match.source, match.slot, anlName)
          if moved > 0 then
            analyzer.activeSpecies[anlName] = info.species or "?"
            tracker.addLog("Analyzing: " .. (info.species or "?") ..
              " " .. (info.type or "bee") .. " (" .. anlName .. ")")
            break  -- This analyzer is loaded, move to next idle one
          end
        end
      end
    end
  end
end

return analyzer
