-- BeeOS Trait Export Layer
-- Exports non-species genetic samples (trait samples) from sample storage
-- to the export chest, keeping only species-chromosome samples.

local inventory = require("lib.inventory")
local tracker = require("lib.tracker")

local traitExport = {}

--- Export trait samples from sample storage to the export chest.
-- Species samples are kept; trait samples (speed, lifespan, etc.) are exported.
-- Uses NBT chromosome field as primary check (0 = species), falls back to
-- matching displayName against catalog + mutation graph species list.
-- @param machines Table from network.scan()
-- @param config BeeOS config
function traitExport.process(machines, config)
  local exportChests = inventory.getExportChests(config)
  if not inventory.first(config.chests.sampleStorage) then return end
  if not inventory.first(exportChests) then return end

  -- Build species lookup from mutation graph for fallback matching
  local allSpeciesSet = {}
  for _, name in ipairs(tracker.allSpecies) do
    allSpeciesSet[name] = true
  end

  -- Find all gene samples in sample storage
  local samples = inventory.findAcross(config.chests.sampleStorage, function(meta)
    local n = meta.name or ""
    return n:find("gene_sample") and not n:find("gene_sample_blank")
  end)

  for _, match in ipairs(samples) do
    local isSpeciesSample = false

    -- Primary: check NBT chromosome field (0 = species)
    local nbt = match.meta.nbt
    if nbt and nbt.chromosome ~= nil then
      isSpeciesSample = (nbt.chromosome == 0)
    else
      -- Fallback: check displayName against catalog + allSpecies
      local displayName = match.meta.displayName or ""
      local label = displayName:match("-%s*(.+)$") or displayName:match(":%s*(.+)$")
      if label then
        isSpeciesSample = tracker.catalog[label] ~= nil or allSpeciesSet[label] ~= nil
      end
    end

    if not isSpeciesSample then
      local moved = inventory.moveTo(match.source, match.slot, exportChests)
      if moved > 0 then
        tracker.addLog("Trait export: " .. (match.meta.displayName or "?") .. " -> export")
      end
    end
  end
end

return traitExport
