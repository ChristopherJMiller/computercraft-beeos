-- BeeOS Bee Library
-- Parses Plethora bee metadata into clean, usable tables.
-- Also handles gene samples and genetic templates.

local bee = {}

--- Normalize a species name by stripping mod registry prefixes.
-- Gendustry custom bees can return internal keys like
-- "gendustry.bees.species.Springwater" when server-side i18n fails.
-- @param name Species display name (may be a registry key)
-- @return Clean species name
function bee.normalizeSpecies(name)
  if not name then return name end
  return name:match("%.bees%.species%.(.+)$") or name
end

--- Compare two species names, tolerant of Gendustry spacing mismatches.
-- e.g. "Springwater" vs "Spring Water" both match.
-- @param a First species name
-- @param b Second species name
-- @return boolean
function bee.speciesMatch(a, b)
  if not a or not b then return false end
  if a == b then return true end
  -- Strip spaces and compare case-insensitively
  return a:gsub("%s", ""):lower() == b:gsub("%s", ""):lower()
end

--- Parse bee info from pre-fetched item metadata.
-- Like inspect() but skips the getItemMeta() call.
-- @param meta Table from getItemMeta()
-- @return Table with species info, or nil if not a bee
function bee.inspectMeta(meta)
  if not meta or not meta.individual then
    return nil
  end

  local beeType
  if meta.name:find("princess") then
    beeType = "princess"
  elseif meta.name:find("queen") then
    beeType = "queen"
  else
    beeType = "drone"
  end

  local g = meta.individual.genome
  if not g then
    -- Unanalyzed bee: extract species from displayName (e.g. "Forest Princess")
    local speciesName = bee.normalizeSpecies((meta.displayName or ""):match("^(.+) %u%l+$"))
    return {
      species = speciesName,
      type = beeType,
      analyzed = false,
      isPurebred = false,
      rawName = meta.name,
      displayName = meta.displayName,
      count = meta.count or 1,
    }
  end

  local active = g.active or {}
  local inactive = g.inactive or {}
  local activeSpecies = active.species or {}
  local inactiveSpecies = inactive.species or {}

  return {
    species = bee.normalizeSpecies(activeSpecies.displayName),
    speciesId = activeSpecies.id,
    inactiveSpecies = bee.normalizeSpecies(inactiveSpecies.displayName),
    inactiveSpeciesId = inactiveSpecies.id,
    isPurebred = activeSpecies.id == inactiveSpecies.id,
    type = beeType,
    analyzed = meta.individual.analyzed,
    pristine = meta.individual.bee and meta.individual.bee.pristine,

    -- Traits
    speed = active.speed,
    lifespan = active.lifespan,
    fertility = active.fertility,
    flowering = active.flowering,
    territory = active.territory,
    effect = active.effect,
    caveDwelling = active.cave_dwelling,
    neverSleeps = active.never_sleeps,
    toleratesRain = active.tolerates_rain,
    temperatureTolerance = active.temperature_tolerance,
    humidityTolerance = active.humidity_tolerance,
    flowerProvider = active.flower_provider,

    -- Raw metadata for advanced use
    rawName = meta.name,
    displayName = meta.displayName,
    count = meta.count or 1,
  }
end

--- Inspect a bee in an inventory slot.
-- @param inventory Wrapped peripheral with getItemMeta
-- @param slot Slot number to inspect
-- @return Table with species info, or nil if not a bee
function bee.inspect(inventory, slot)
  return bee.inspectMeta(inventory.getItemMeta(slot))
end

--- Check if an item in a slot is any kind of bee (princess, drone, or queen).
-- @param inventory Wrapped peripheral
-- @param slot Slot number
-- @return boolean
function bee.isBee(inventory, slot)
  local meta = inventory.getItemMeta(slot)
  if not meta then return false end
  local name = meta.name or ""
  return name:find("bee_drone") or name:find("bee_princess") or name:find("bee_queen")
end

--- Check if a slot contains a drone.
function bee.isDrone(inventory, slot)
  local meta = inventory.getItemMeta(slot)
  if not meta then return false end
  return (meta.name or ""):find("bee_drone") ~= nil
end

--- Check if a slot contains a princess.
function bee.isPrincess(inventory, slot)
  local meta = inventory.getItemMeta(slot)
  if not meta then return false end
  return (meta.name or ""):find("bee_princess") ~= nil
end

--- Check if a slot contains a queen.
function bee.isQueen(inventory, slot)
  local meta = inventory.getItemMeta(slot)
  if not meta then return false end
  return (meta.name or ""):find("bee_queen") ~= nil
end

--- Inspect a gene sample in an inventory slot.
-- @param inventory Wrapped peripheral
-- @param slot Slot number
-- @return Table with sample info, or nil if not a gene sample
function bee.inspectSample(inventory, slot)
  local meta = inventory.getItemMeta(slot)
  if not meta then return nil end

  local name = meta.name or ""
  if not name:find("gene_sample") then return nil end

  return {
    displayName = meta.displayName,
    rawName = meta.name,
    count = meta.count or 1,
    -- The display name typically contains the trait info, e.g. "Gene Sample: Forest"
    -- Exact structure depends on what getItemMeta returns for gene samples
    -- Phase 0 inspect tool will reveal the actual format
    raw = meta,
  }
end

--- Check if a slot contains a gene sample.
function bee.isGeneSample(inventory, slot)
  local meta = inventory.getItemMeta(slot)
  if not meta then return false end
  return (meta.name or ""):find("gene_sample") ~= nil
end

--- Check if a slot contains a genetic template.
function bee.isGeneticTemplate(inventory, slot)
  local meta = inventory.getItemMeta(slot)
  if not meta then return false end
  return (meta.name or ""):find("gene_template") ~= nil
end

--- Check if a slot contains a blank genetic template.
function bee.isBlankTemplate(inventory, slot)
  local meta = inventory.getItemMeta(slot)
  if not meta then return false end
  local name = meta.name or ""
  -- Blank template: gene_template with no NBT data (no nbtHash)
  -- Filled templates have NBT containing species + samples
  return name:find("gene_template") ~= nil and meta.nbtHash == nil
end

--- Check if a slot contains genetic waste (failed imprinting byproduct).
-- @param inventory Wrapped peripheral
-- @param slot Slot number
-- @return boolean
function bee.isGeneticWaste(inventory, slot)
  local meta = inventory.getItemMeta(slot)
  if not meta then return false end
  return (meta.name or ""):find("waste") ~= nil
end

--- Get a quick species summary string for display purposes.
-- @param beeInfo Table returned by bee.inspect()
-- @return String like "Forest (pure)" or "Forest/Meadows"
function bee.speciesLabel(beeInfo)
  if not beeInfo then return "?" end
  if beeInfo.isPurebred then
    return beeInfo.species .. " (pure)"
  else
    return beeInfo.species .. "/" .. (beeInfo.inactiveSpecies or "?")
  end
end

--- Check if a slot contains labware (consumed by sampler, imprinter, mutatron).
function bee.isLabware(inventory, slot)
  local meta = inventory.getItemMeta(slot)
  if not meta then return false end
  return (meta.name or ""):find("labware") ~= nil
end

return bee
