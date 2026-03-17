-- BeeOS Layer 0: Passive Tracker
-- Scans all inventories on the network and builds a species catalog.
-- Read-only — never moves items.

local state = require("lib.state")
local bee = require("lib.bee")


local tracker = {}

-- Item name patterns that indicate bee-related items worth full metadata scan
local BEE_NAME_PATTERNS = {
  "princess", "drone", "queen",
  "gene_sample", "gene_template",
}

--- Check if an item registry name is bee-related.
-- @param itemName Registry name from list() (e.g. "forestry:bee_drone_ge")
-- @return boolean
local function isBeeRelated(itemName)
  for _, pattern in ipairs(BEE_NAME_PATTERNS) do
    if itemName:find(pattern) then
      return true
    end
  end
  return false
end

-- Species catalog: { [speciesName] = { samples, templates, drones, princesses, queens } }
tracker.catalog = {}

-- All known species from mutation graph (populated by Layer 3 if available)
tracker.allSpecies = {}

-- Activity log (recent events)
tracker.log = {}
local MAX_LOG = 200

--- Add an entry to the activity log.
function tracker.addLog(message)
  local entry = {
    time = os.clock(),
    day = os.day(),
    message = message,
  }
  table.insert(tracker.log, 1, entry)
  if #tracker.log > MAX_LOG then
    table.remove(tracker.log)
  end
end

--- Scan all inventories and rebuild the species catalog.
-- @param machines Table from network.scan()
-- @param config Optional BeeOS config
function tracker.scan(machines, config)
  local catalog = {}

  -- Resolve a species name to an existing catalog key via fuzzy match.
  -- Returns the existing key if one matches, otherwise the original name.
  local function resolveSpecies(species)
    if catalog[species] then return species end
    for existing in pairs(catalog) do
      if bee.speciesMatch(existing, species) then return existing end
    end
    return species
  end

  -- Helper to ensure a species entry exists
  local function ensure(species)
    if not catalog[species] then
      catalog[species] = {
        samples = 0,
        templates = 0,
        drones = 0,
        princesses = 0,
        queens = 0,
        discovered = true,
      }
    end
  end

  -- Scan all storage peripherals
  local allInventories = {}
  for name, p in pairs(machines.chest or {}) do
    allInventories[name] = p
  end
  -- Also scan apiaries for current queens/drones
  for name, p in pairs(machines.apiary or {}) do
    allInventories[name] = p
  end

  local inventoryCount = 0
  local itemCount = 0

  -- Two-pass scan: first create catalog entries from bees, then count samples/templates.
  -- pairs() iteration order is non-deterministic, so samples/templates may be
  -- encountered before the bees that create their catalog entries.
  local deferred = {}

  for periName, p in pairs(allInventories) do
    inventoryCount = inventoryCount + 1

    if p.list then
      -- Fast path: list() returns all occupied slots in a single call.
      -- Only call expensive getItemMeta() on bee-related slots.
      local listing = p.list()
      for slot, info in pairs(listing) do
        itemCount = itemCount + 1
        if isBeeRelated(info.name) and p.getItemMeta then
          local meta = p.getItemMeta(slot)
          if meta then
            local name = meta.name or ""

            if meta.individual then
              local speciesName
              if meta.individual.genome then
                local species = (meta.individual.genome.active or {}).species
                speciesName = bee.normalizeSpecies(species and species.displayName)
              end
              if not speciesName then
                speciesName = bee.normalizeSpecies(
                  (meta.displayName or ""):match("^(.+) %u%l+$"))
              end
              if speciesName then
                ensure(speciesName)
                if name:find("princess") then
                  catalog[speciesName].princesses =
                    catalog[speciesName].princesses + (meta.count or 1)
                elseif name:find("queen") then
                  catalog[speciesName].queens =
                    catalog[speciesName].queens + 1
                else
                  catalog[speciesName].drones =
                    catalog[speciesName].drones + (meta.count or 1)
                end
              end

            elseif name:find("gene_sample") and not name:find("gene_sample_blank") then
              deferred[#deferred + 1] = { meta = meta, periName = periName }
            elseif name:find("gene_template") then
              deferred[#deferred + 1] = { meta = meta, periName = periName }
            end
          end
        end
      end
    else
      -- Fallback: scan all slots sequentially
      local size = p.size and p.size() or 0
      for slot = 1, size do
        local meta
        if p.getItemMeta then
          meta = p.getItemMeta(slot)
        end
        if meta then
          itemCount = itemCount + 1
          local name = meta.name or ""

          if meta.individual then
            local speciesName
            if meta.individual.genome then
              local species = (meta.individual.genome.active or {}).species
              speciesName = bee.normalizeSpecies(species and species.displayName)
            end
            if not speciesName then
              speciesName = bee.normalizeSpecies(
                (meta.displayName or ""):match("^(.+) %u%l+$"))
            end
            if speciesName then
              ensure(speciesName)
              if name:find("princess") then
                catalog[speciesName].princesses =
                  catalog[speciesName].princesses + (meta.count or 1)
              elseif name:find("queen") then
                catalog[speciesName].queens =
                  catalog[speciesName].queens + 1
              else
                catalog[speciesName].drones =
                  catalog[speciesName].drones + (meta.count or 1)
              end
            end

          elseif name:find("gene_sample") and not name:find("gene_sample_blank") then
            deferred[#deferred + 1] = { meta = meta, periName = periName }
          elseif name:find("gene_template") then
            deferred[#deferred + 1] = { meta = meta, periName = periName }
          end
        end
      end
    end
  end

  -- Pass 2: Count samples and templates (all catalog entries now exist)
  local unknownTemplates = 0
  local templateMap = state.load("template_hashes", {})

  for _, entry in ipairs(deferred) do
    local meta = entry.meta
    local name = meta.name or ""

    if name:find("gene_sample") then
      -- Format: "Bee Sample - Species: Forest" or "Bee Sample - Speed: Fastest"
      local displayName = meta.displayName or ""
      -- Extract species name from "Species: <name>" pattern
      local speciesName = bee.normalizeSpecies(displayName:match("Species:%s*(.+)$"))
      if speciesName then
        speciesName = resolveSpecies(speciesName)
        ensure(speciesName)
        catalog[speciesName].samples =
          catalog[speciesName].samples + (meta.count or 1)
      end

    elseif name:find("gene_template") and meta.nbtHash then
      -- Templates have no species in displayName — use learned nbtHash mapping
      local templateSpecies = templateMap[meta.nbtHash]
      if templateSpecies then
        templateSpecies = resolveSpecies(templateSpecies)
        ensure(templateSpecies)
        catalog[templateSpecies].templates =
          catalog[templateSpecies].templates + (meta.count or 1)
      else
        unknownTemplates = unknownTemplates + 1
      end
    end
  end

  if unknownTemplates > 0 then
    tracker.addLog(unknownTemplates .. " template(s) with unknown hash"
      .. " (run 'learn' tool to fix)")
  end

  -- Detect new discoveries
  for species in pairs(catalog) do
    if not tracker.catalog[species] then
      tracker.addLog("New species detected: " .. species)
    end
  end

  -- Detect low samples
  for species, data in pairs(catalog) do
    if data.samples > 0 and data.samples <= 1 then
      -- Only warn if we previously had more
      local prev = tracker.catalog[species]
      if prev and prev.samples > 1 then
        tracker.addLog("LOW SAMPLES: " .. species .. " (" .. data.samples .. " remaining)")
      end
    end
  end

  tracker.catalog = catalog

  -- Persist
  state.save("catalog", catalog)
  state.save("log", tracker.log)

  return inventoryCount, itemCount
end

--- Get the status color for a species.
-- @param speciesData Table from catalog
-- @return CC color constant
function tracker.statusColor(speciesData)
  if not speciesData or not speciesData.discovered then
    return colors.gray  -- Undiscovered
  end
  if speciesData.samples == 0 and speciesData.drones == 0 then
    return colors.red  -- No samples, needs attention
  end
  if speciesData.samples < 3 or speciesData.templates == 0 then
    return colors.orange  -- Low samples or missing template
  end
  return colors.lime  -- Fully stocked
end

--- Get sorted species list for display.
-- @return List of { name, data, color }
function tracker.sortedSpecies()
  local list = {}
  -- Include catalog species
  for name, data in pairs(tracker.catalog) do
    list[#list + 1] = {
      name = name,
      data = data,
      color = tracker.statusColor(data),
    }
  end
  -- Include undiscovered species from allSpecies
  for _, name in ipairs(tracker.allSpecies) do
    if not tracker.catalog[name] then
      list[#list + 1] = {
        name = name,
        data = { samples = 0, templates = 0, drones = 0, princesses = 0, queens = 0, discovered = false },
        color = colors.gray,
      }
    end
  end
  -- Sort: red first, then orange, then green, then gray, alphabetical within
  local colorOrder = { [colors.red] = 1, [colors.orange] = 2, [colors.lime] = 3, [colors.gray] = 4 }
  table.sort(list, function(a, b)
    local ao = colorOrder[a.color] or 5
    local bo = colorOrder[b.color] or 5
    if ao ~= bo then return ao < bo end
    return a.name < b.name
  end)
  return list
end

--- Load persisted state on startup.
function tracker.restore()
  tracker.catalog = state.load("catalog", {})
  tracker.log = state.load("log", {})
end

--- Get summary statistics.
-- @return Table with counts
function tracker.stats()
  local discovered = 0
  local fullyStocked = 0
  local needsAttention = 0
  local totalSamples = 0

  for _, data in pairs(tracker.catalog) do
    discovered = discovered + 1
    totalSamples = totalSamples + data.samples
    local color = tracker.statusColor(data)
    if color == colors.lime then
      fullyStocked = fullyStocked + 1
    elseif color == colors.red or color == colors.orange then
      needsAttention = needsAttention + 1
    end
  end

  return {
    discovered = discovered,
    total = discovered + #tracker.allSpecies, -- approximate
    fullyStocked = fullyStocked,
    needsAttention = needsAttention,
    totalSamples = totalSamples,
  }
end

return tracker
