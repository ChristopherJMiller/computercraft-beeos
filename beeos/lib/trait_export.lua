-- BeeOS Trait Export Layer
-- Exports non-species genetic samples (trait samples) from sample storage
-- to the export chest, keeping only species-chromosome samples.

local inventory = require("lib.inventory")
local tracker = require("lib.tracker")

local traitExport = {}

--- Export trait samples from sample storage to the export chest.
-- Species samples (displayName contains "Species:") are kept.
-- All other samples (speed, lifespan, etc.) are exported.
-- @param machines Table from network.scan()
-- @param config BeeOS config
function traitExport.process(machines, config)
  local exportChests = inventory.getExportChests(config)
  if not inventory.first(config.chests.sampleStorage) then return end
  if not inventory.first(exportChests) then return end

  -- Find all gene samples in sample storage
  local samples = inventory.findAcross(config.chests.sampleStorage, function(meta)
    local n = meta.name or ""
    return n:find("gene_sample") and not n:find("gene_sample_blank")
  end)

  for _, match in ipairs(samples) do
    local displayName = match.meta.displayName or ""
    local isSpeciesSample = displayName:find("Species:") ~= nil

    if not isSpeciesSample then
      local moved = inventory.moveTo(match.source, match.slot, exportChests)
      if moved > 0 then
        tracker.addLog("Trait export: " .. displayName .. " -> export")
      end
    end
  end
end

return traitExport
