-- BeeOS Trait Export Layer
-- Exports non-species genetic samples (trait samples) from sample storage
-- to the export chest. Also exports surplus species samples above threshold.

local bee = require("lib.bee")
local inventory = require("lib.inventory")
local tracker = require("lib.tracker")

local traitExport = {}

--- Export trait samples and surplus species samples from sample storage.
-- Non-species samples (speed, lifespan, etc.) are always exported.
-- Species samples above minSamplesPerSpecies are also exported.
-- @param machines Table from network.scan()
-- @param config BeeOS config
function traitExport.process(machines, config)
  local exportChests = inventory.getExportChests(config)
  if not inventory.first(config.chests.sampleStorage) then return end
  if not inventory.first(exportChests) then return end

  local threshold = config.thresholds.minSamplesPerSpecies or 3

  -- Find all gene samples in sample storage
  local samples = inventory.findAcross(config.chests.sampleStorage, function(meta)
    local n = meta.name or ""
    return n:find("gene_sample") and not n:find("gene_sample_blank")
  end)

  -- Count species samples so we can export only the surplus
  -- { [normalizedSpecies] = { count, slots } }
  local speciesCounts = {}

  -- First pass: categorize and count
  for _, match in ipairs(samples) do
    local displayName = match.meta.displayName or ""
    local speciesName = (displayName):match("Species:%s*(.+)$")

    if speciesName then
      local norm = bee.normalizeSpecies(speciesName)
      if not speciesCounts[norm] then
        speciesCounts[norm] = { count = 0, slots = {} }
      end
      speciesCounts[norm].count = speciesCounts[norm].count + (match.meta.count or 1)
      speciesCounts[norm].slots[#speciesCounts[norm].slots + 1] = match
    end
  end

  -- Second pass: export trait samples and surplus species samples
  for _, match in ipairs(samples) do
    local displayName = match.meta.displayName or ""
    local speciesName = (displayName):match("Species:%s*(.+)$")

    if not speciesName then
      -- Non-species sample (trait) — always export
      local moved = inventory.moveTo(match.source, match.slot, exportChests)
      if moved > 0 then
        tracker.addLog("Trait export: " .. displayName .. " -> export")
      end
    else
      -- Species sample — export if above threshold
      local norm = bee.normalizeSpecies(speciesName)
      local entry = speciesCounts[norm]
      if entry and entry.count > threshold then
        local moved = inventory.moveTo(match.source, match.slot, exportChests,
          nil, entry.count - threshold)
        if moved > 0 then
          entry.count = entry.count - moved
          tracker.addLog("Surplus sample: " .. norm .. " -> export (" .. entry.count .. " kept)")
        end
      end
    end
  end
end

return traitExport
