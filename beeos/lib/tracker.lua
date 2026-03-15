-- BeeOS Layer 0: Passive Tracker
-- Scans all inventories on the network and builds a species catalog.
-- Read-only — never moves items.

local state = require("lib.state")

local tracker = {}

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
function tracker.scan(machines)
  local catalog = {}

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

  for periName, p in pairs(allInventories) do
    inventoryCount = inventoryCount + 1
    local size = p.size and p.size() or 0
    for slot = 1, size do
      local meta
      if p.getItemMeta then
        meta = p.getItemMeta(slot)
      end
      if meta then
        itemCount = itemCount + 1
        local name = meta.name or ""

        -- Check for bees
        if meta.individual then
          local speciesName
          if meta.individual.genome then
            -- Analyzed bee: read species from genome
            local species = (meta.individual.genome.active or {}).species
            speciesName = species and species.displayName
          end
          if not speciesName then
            -- Unanalyzed bee: parse from displayName (e.g. "Forest Princess")
            speciesName = (meta.displayName or ""):match("^(.+) %u%l+$")
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

        -- Check for gene samples
        elseif name:find("gene_sample") then
          -- Try to extract species from display name
          local sampleSpecies = (meta.displayName or ""):match(":%s*(.+)$")
          if sampleSpecies then
            ensure(sampleSpecies)
            catalog[sampleSpecies].samples =
              catalog[sampleSpecies].samples + (meta.count or 1)
          end

        -- Check for genetic templates
        elseif name:find("gene_template") and meta.damage and meta.damage > 0 then
          -- Filled templates have damage > 0 (or NBT data)
          -- Extracting species from template display name
          local templateSpecies = (meta.displayName or ""):match(":%s*(.+)$")
          if templateSpecies then
            ensure(templateSpecies)
            catalog[templateSpecies].templates =
              catalog[templateSpecies].templates + (meta.count or 1)
          end
        end
      end
    end
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
