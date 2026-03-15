-- BeeOS Layer 2: Sample & Template Manager
-- Manages genetic sampling of drones and template crafting.

local bee = require("lib.bee")
local inventory = require("lib.inventory")
local tracker = require("lib.tracker")
local state = require("lib.state")

local sampler = {}

-- Current state
sampler.state = "idle"  -- idle, sampling, waiting_output
sampler.activeSpecies = {}  -- { [machineNamea] = speciesName }
sampler.activeTransposer = {}  -- { [machineName] = speciesName }
sampler.pendingTemplate = nil  -- species name of template being crafted

--- Process drones in the buffer: route to sampler or surplus.
-- Discovery-needed species are routed first when prioritySpecies is provided.
-- @param machines Table from network.scan()
-- @param config BeeOS config
-- @param prioritySpecies Optional set { [species] = true } to route first
function sampler.processDrones(machines, config, prioritySpecies)
  if not inventory.first(config.chests.droneBuffer) then return end

  local thresholds = config.thresholds

  local allDrones = inventory.findAcross(config.chests.droneBuffer, function(meta)
    return (meta.name or ""):find("bee_drone") ~= nil
  end)

  -- Sort priority species to front if provided
  if prioritySpecies and next(prioritySpecies) then
    -- Inspect all drones to get species, then sort
    local inspected = {}
    for _, match in ipairs(allDrones) do
      local bufPeri = peripheral.wrap(match.source)
      local info = bufPeri and bee.isDrone(bufPeri, match.slot)
        and bee.inspect(bufPeri, match.slot)
      inspected[#inspected + 1] = { match = match, info = info }
    end
    table.sort(inspected, function(a, b)
      local aPri = a.info and prioritySpecies[a.info.species] or false
      local bPri = b.info and prioritySpecies[b.info.species] or false
      if aPri ~= bPri then return aPri end
      return false  -- stable for equal priority
    end)
    -- Process sorted list (already inspected)
    for _, entry in ipairs(inspected) do
      local info = entry.info
      if info and info.species then
        local catalogEntry = tracker.catalog[info.species]
        local sampleCount = catalogEntry and catalogEntry.samples or 0
        local droneCount = catalogEntry and catalogEntry.drones or 0
        local match = entry.match
        -- Discovery-needed samples can dip into the reserve
        local needsSample = prioritySpecies[info.species] == "sample"
        local minDrones = needsSample
          and thresholds.minDronesPerSpecies
          or (thresholds.minDronesPerSpecies + 1)

        if sampleCount == 0 and droneCount >= minDrones then
          sampler.sendToSampler(match.source, match.slot, machines, config)
        elseif sampleCount < thresholds.minSamplesPerSpecies
            and sampleCount >= 1 and droneCount > thresholds.minDronesPerSpecies
            and not sampler.hasTransposer(machines, config) then
          sampler.sendToSampler(match.source, match.slot, machines, config)
        elseif droneCount > thresholds.maxDronesPerSpecies then
          local exportChests = inventory.getExportChests(config)
          if inventory.first(exportChests) then
            inventory.moveTo(match.source, match.slot, exportChests)
            tracker.addLog("Surplus drone: " .. info.species .. " -> DNA")
          end
        end
      end
    end
  else
    -- No priority sorting needed
    for _, match in ipairs(allDrones) do
      local bufPeri = peripheral.wrap(match.source)
      if bufPeri and bee.isDrone(bufPeri, match.slot) then
        local info = bee.inspect(bufPeri, match.slot)
        if info and info.species then
          local catalogEntry = tracker.catalog[info.species]
          local sampleCount = catalogEntry and catalogEntry.samples or 0
          local droneCount = catalogEntry and catalogEntry.drones or 0

          if sampleCount == 0
              and droneCount > thresholds.minDronesPerSpecies then
            sampler.sendToSampler(match.source, match.slot, machines, config)
          elseif sampleCount < thresholds.minSamplesPerSpecies
              and sampleCount >= 1 and droneCount > thresholds.minDronesPerSpecies
              and not sampler.hasTransposer(machines, config) then
            sampler.sendToSampler(match.source, match.slot, machines, config)
          elseif droneCount > thresholds.maxDronesPerSpecies then
            local exportChests = inventory.getExportChests(config)
            if inventory.first(exportChests) then
              inventory.moveTo(match.source, match.slot, exportChests)
              tracker.addLog("Surplus drone: " .. info.species .. " -> DNA")
            end
          end
        end
      end
    end
  end
end

--- Send a drone to the Genetic Sampler.
-- @param fromPeri Source peripheral name
-- @param fromSlot Source slot
-- @param machines Table from network.scan()
-- @param config BeeOS config
-- @return boolean success
function sampler.sendToSampler(fromPeri, fromSlot, machines, config)
  -- Build list of all available samplers
  local samplers = {}
  if config.machines.samplers then
    for _, name in ipairs(config.machines.samplers) do
      samplers[name] = peripheral.wrap(name)
    end
  else
    samplers = machines.sampler or {}
  end

  -- Try each sampler until we find an idle one
  for samplerName, sampPeri in pairs(samplers) do
    if sampPeri then
      -- Check if sampler is busy
      local busy = false
      local sampSize = sampPeri.size and sampPeri.size() or 0
      for slot = 1, sampSize do
        local meta = sampPeri.getItemMeta and sampPeri.getItemMeta(slot)
        if meta then
          local n = meta.name or ""
          if n:find("gene_sample") and not n:find("gene_sample_blank") then
            busy = true; break
          end
          if n:find("bee_") then
            busy = true; break
          end
        end
      end

      if not busy then
        -- Ensure labware and blank samples
        sampler.ensureLabware(samplerName, machines, config)
        sampler.ensureBlankSamples(samplerName, machines, config)

        -- Inspect before moving (slot will be empty after move)
        local info = bee.inspect(peripheral.wrap(fromPeri), fromSlot)
        local species = info and info.species or "Unknown"

        -- Send the drone
        local moved = inventory.move(fromPeri, fromSlot, samplerName)
        if moved > 0 then
          sampler.state = "sampling"
          sampler.activeSpecies[samplerName] = species
          tracker.addLog("Sampling: " .. species .. " (" .. samplerName .. ")")
          return true
        end
      end
    end
  end

  return false
end

--- Ensure the sampler has labware available.
-- Pulls from supply chest if needed.
function sampler.ensureLabware(samplerName, machines, config)
  if not inventory.first(config.chests.supplyInput) then return end

  local matches = inventory.findAcross(config.chests.supplyInput, function(meta)
    return (meta.name or ""):find("labware") ~= nil
  end)

  if matches[1] then
    inventory.move(matches[1].source, matches[1].slot, samplerName, nil, 1)
  end
end

--- Ensure blank gene samples are in the sampler.
function sampler.ensureBlankSamples(samplerName, machines, config)
  if not inventory.first(config.chests.supplyInput) then return end

  local matches = inventory.findAcross(config.chests.supplyInput, function(meta)
    return (meta.name or ""):find("gene_sample_blank") ~= nil
  end)

  if matches[1] then
    inventory.move(matches[1].source, matches[1].slot, samplerName, nil, 1)
  end
end

--- Collect output from a single sampler machine.
-- Extracts gene samples, spent drones, waste, and unused blanks.
-- @param samplerName Peripheral name
-- @param samplerPeri Wrapped peripheral
-- @param config BeeOS config
function sampler.collectFromSampler(samplerName, samplerPeri, config)
  local size = samplerPeri.size and samplerPeri.size() or 0
  local hasItems = false
  for slot = 1, size do
    local meta = samplerPeri.getItemMeta and samplerPeri.getItemMeta(slot)
    if meta then
      local itemName = meta.name or ""
      local moved = false
      if itemName:find("gene_sample_blank") then
        -- Unused blank sample → return to supply
        if inventory.first(config.chests.supplyInput) then
          inventory.moveTo(samplerName, slot, config.chests.supplyInput)
          moved = true
        end
      elseif itemName:find("gene_sample") then
        -- Completed gene sample → sample storage
        local displayName = meta.displayName or ""
        local movedCount = inventory.moveTo(samplerName, slot, config.chests.sampleStorage)
        if movedCount > 0 then
          moved = true
          -- Check if this is a species sample
          -- Format: "Bee Sample - Species: Forest"
          local isSpeciesSample = displayName:find("Species:") ~= nil
          local currentSp = sampler.activeSpecies[samplerName]
          if isSpeciesSample then
            tracker.addLog("Species sample: " .. currentSp .. " -> storage")
            sampler.activeSpecies[samplerName] = nil
            -- Set state to idle only if no other samplers are active
            if not next(sampler.activeSpecies) then
              sampler.state = "idle"
            end
          else
            -- Got a trait sample (speed, lifespan, etc.) — still useful
            -- but keep sampling for the species chromosome
            tracker.addLog("Trait sample: " .. displayName .. " -> storage")
          end
        end
      elseif itemName:find("bee_drone") then
        -- Spent drone returned by sampler → drone buffer
        if inventory.first(config.chests.droneBuffer) then
          inventory.moveTo(samplerName, slot, config.chests.droneBuffer)
          moved = true
        end
      elseif itemName:find("bee_") then
        -- Any other bee output → drone buffer
        if inventory.first(config.chests.droneBuffer) then
          inventory.moveTo(samplerName, slot, config.chests.droneBuffer)
          moved = true
        end
      elseif itemName:find("waste") then
        -- Genetic waste → export
        local exportChests = inventory.getExportChests(config)
        if inventory.first(exportChests) then
          inventory.moveTo(samplerName, slot, exportChests)
          moved = true
        end
      end
      if not moved then hasItems = true end
    end
  end

  -- Clear status if sampler is empty (all items collected or consumed)
  if not hasItems and sampler.activeSpecies[samplerName] then
    sampler.activeSpecies[samplerName] = nil
    if not next(sampler.activeSpecies) then
      sampler.state = "idle"
    end
  end
end

--- Check all sampler machines and collect completed output.
-- @param machines Table from network.scan()
-- @param config BeeOS config
function sampler.collectOutput(machines, config)
  if not inventory.first(config.chests.sampleStorage) then return end

  local samplers = {}
  if config.machines.samplers then
    for _, name in ipairs(config.machines.samplers) do
      samplers[name] = peripheral.wrap(name)
    end
  else
    samplers = machines.sampler or {}
  end

  for samplerName, samplerPeri in pairs(samplers) do
    sampler.collectFromSampler(samplerName, samplerPeri, config)
  end
end

-- Transposer slot constants (from Gendustry source: TileTransposer.scala)
local TRANSPOSER_BLANK = 1    -- Slot 0 (1-indexed): blank gene sample input
-- Labware goes to slot 1 (1-indexed) via ensureLabware()
local TRANSPOSER_SOURCE = 3   -- Slot 2 (1-indexed): source sample (NOT consumed)
local TRANSPOSER_OUTPUT = 4   -- Slot 3 (1-indexed): output copy

--- Get all available transposers (config override or auto-detected).
-- @param machines Table from network.scan()
-- @param config BeeOS config
-- @return Table of { [name] = wrappedPeripheral }
function sampler.getTransposers(machines, config)
  local transposers = {}
  if config.machines.transposers then
    for _, name in ipairs(config.machines.transposers) do
      transposers[name] = peripheral.wrap(name)
    end
  else
    transposers = machines.transposer or {}
  end
  return transposers
end

--- Check if any transposer is available on the network.
-- @param machines Table from network.scan()
-- @param config BeeOS config
-- @return boolean
function sampler.hasTransposer(machines, config)
  local transposers = sampler.getTransposers(machines, config)
  return next(transposers) ~= nil
end

--- Identify the species of a gene sample from its displayName.
-- @param meta Item metadata table
-- @return species name or nil
local function sampleSpecies(meta)
  if not meta then return nil end
  local name = meta.name or ""
  if not name:find("gene_sample") or name:find("gene_sample_blank") then
    return nil
  end
  local species = (meta.displayName or ""):match("Species:%s*(.+)$")
  return species and bee.normalizeSpecies(species) or nil
end

--- Try to start duplication on a single transposer.
-- @return true if started, false to try next transposer, nil to abort
local function tryTransposer(tName, tPeri, species, config)
  -- Check if this transposer is already working on this species
  if sampler.activeTransposer[tName] == species then
    return true  -- Already duplicating
  end

  -- Check if transposer is idle (no output pending, no blank loaded)
  local outMeta = tPeri.getItemMeta and tPeri.getItemMeta(TRANSPOSER_OUTPUT)
  local blankMeta = tPeri.getItemMeta and tPeri.getItemMeta(TRANSPOSER_BLANK)
  if outMeta or blankMeta then
    return false  -- Busy
  end

  -- Check source slot: may have a previous species' sample
  local sourceMeta = tPeri.getItemMeta and tPeri.getItemMeta(TRANSPOSER_SOURCE)
  if sourceMeta then
    local sourceSpecies = sampleSpecies(sourceMeta)
    if not bee.speciesMatch(sourceSpecies, species) then
      -- Wrong species — return it to storage
      local returned = inventory.moveTo(tName, TRANSPOSER_SOURCE,
        config.chests.sampleStorage)
      if returned == 0 then return false end
      sourceMeta = nil
    end
  end

  -- Load source sample if needed
  if not sourceMeta then
    local sampleMatches = inventory.findAcross(config.chests.sampleStorage,
      function(meta)
        return bee.speciesMatch(sampleSpecies(meta), species)
      end)
    if not sampleMatches[1] then return nil end  -- No sample available anywhere
    local moved = inventory.move(sampleMatches[1].source,
      sampleMatches[1].slot, tName, TRANSPOSER_SOURCE, 1)
    if moved == 0 then return false end
  end

  -- Load blank gene sample
  local blankMatches = inventory.findAcross(config.chests.supplyInput,
    function(meta)
      return (meta.name or ""):find("gene_sample_blank") ~= nil
    end)
  if not blankMatches[1] then
    tracker.addLog("Transposer: no blank samples available")
    return nil  -- No blanks anywhere
  end
  inventory.move(blankMatches[1].source, blankMatches[1].slot,
    tName, TRANSPOSER_BLANK, 1)

  -- Load labware
  sampler.ensureLabware(tName, nil, config)

  sampler.activeTransposer[tName] = species
  tracker.addLog("Duplicating sample: " .. species .. " (" .. tName .. ")")
  return true
end

--- Start duplicating a species sample in a transposer.
-- Finds an idle transposer, loads the source sample, blank, and labware.
-- @param species Species name to duplicate
-- @param machines Table from network.scan()
-- @param config BeeOS config
-- @return boolean success
function sampler.duplicateSample(species, machines, config)
  if not inventory.first(config.chests.sampleStorage) then return false end
  if not inventory.first(config.chests.supplyInput) then return false end

  local transposers = sampler.getTransposers(machines, config)

  for tName, tPeri in pairs(transposers) do
    if tPeri then
      local result = tryTransposer(tName, tPeri, species, config)
      if result == true then return true end
      if result == nil then return false end  -- Abort (no samples/blanks)
      -- result == false: try next transposer
    end
  end

  return false
end

--- Process a single transposer's output and state.
local function processTransposerOutput(tName, tPeri, config)
  local species = sampler.activeTransposer[tName]

  -- Check output slot
  local outMeta = tPeri.getItemMeta and tPeri.getItemMeta(TRANSPOSER_OUTPUT)
  if outMeta then
    -- Move copy to sample storage
    if inventory.first(config.chests.sampleStorage) then
      local moved = inventory.moveTo(tName, TRANSPOSER_OUTPUT,
        config.chests.sampleStorage)
      if moved > 0 then
        tracker.addLog("Duplicated sample: " .. (species or "?") .. " -> storage")
      end
    end
  end

  -- If we're tracking this transposer, check if species is now fully stocked
  if not species then
    -- Defensive: clear stranded blanks from untracked transposers
    local staleBlank = tPeri.getItemMeta
      and tPeri.getItemMeta(TRANSPOSER_BLANK)
    if staleBlank then
      if inventory.first(config.chests.supplyInput) then
        inventory.moveTo(tName, TRANSPOSER_BLANK, config.chests.supplyInput)
      end
    end
    return
  end

  local catalogEntry = tracker.catalog[species]
  local sampleCount = catalogEntry and catalogEntry.samples or 0

  if sampleCount >= (config.thresholds.minSamplesPerSpecies or 3) then
    -- Fully stocked — return source sample to storage
    local sourceMeta = tPeri.getItemMeta
      and tPeri.getItemMeta(TRANSPOSER_SOURCE)
    if sourceMeta then
      inventory.moveTo(tName, TRANSPOSER_SOURCE, config.chests.sampleStorage)
      tracker.addLog("Transposer done: " .. species .. " fully stocked")
    end
    -- Return any loaded blank that won't be needed (prevents stranding)
    local staleBlank = tPeri.getItemMeta
      and tPeri.getItemMeta(TRANSPOSER_BLANK)
    if staleBlank then
      inventory.moveTo(tName, TRANSPOSER_BLANK, config.chests.supplyInput)
    end
    sampler.activeTransposer[tName] = nil
  else
    -- Still need more — reload a blank if the machine is idle
    local blankMeta = tPeri.getItemMeta
      and tPeri.getItemMeta(TRANSPOSER_BLANK)
    local outStillThere = tPeri.getItemMeta
      and tPeri.getItemMeta(TRANSPOSER_OUTPUT)
    if not blankMeta and not outStillThere then
      -- Load another blank
      local blankMatches = inventory.findAcross(config.chests.supplyInput,
        function(meta)
          return (meta.name or ""):find("gene_sample_blank") ~= nil
        end)
      if blankMatches[1] then
        inventory.move(blankMatches[1].source, blankMatches[1].slot,
          tName, TRANSPOSER_BLANK, 1)
      end
      -- Top up labware (20% consumption chance)
      sampler.ensureLabware(tName, nil, config)
    end
  end
end

--- Collect output from transposers and manage their state.
-- Picks up completed copies, reloads blanks for continued duplication,
-- or returns the source sample when the species is fully stocked.
-- @param machines Table from network.scan()
-- @param config BeeOS config
function sampler.collectTransposerOutput(machines, config)
  local transposers = sampler.getTransposers(machines, config)

  for tName, tPeri in pairs(transposers) do
    if tPeri then
      processTransposerOutput(tName, tPeri, config)
    end
  end
end

--- Extract all items from transposers (used during shutdown).
-- Returns source samples and copies to sampleStorage, blanks to supplyInput.
-- @param machines Table from network.scan()
-- @param config BeeOS config
function sampler.extractTransposers(machines, config)
  local transposers = sampler.getTransposers(machines, config)

  -- Multiple passes: machines mid-process may produce output after first scan
  for pass = 1, 3 do
    local foundAny = false
    for tName, tPeri in pairs(transposers) do
      if tPeri then
        local size = tPeri.size and tPeri.size() or 0
        for slot = 1, size do
          local meta = tPeri.getItemMeta and tPeri.getItemMeta(slot)
          if meta then
            foundAny = true
            local itemName = meta.name or ""
            if itemName:find("gene_sample_blank") then
              if inventory.first(config.chests.supplyInput) then
                inventory.moveTo(tName, slot, config.chests.supplyInput)
              end
            elseif itemName:find("gene_sample") then
              if inventory.first(config.chests.sampleStorage) then
                inventory.moveTo(tName, slot, config.chests.sampleStorage)
              end
            elseif itemName:find("labware") then
              if inventory.first(config.chests.supplyInput) then
                inventory.moveTo(tName, slot, config.chests.supplyInput)
              end
            end
          end
        end
        sampler.activeTransposer[tName] = nil
      end
    end
    if not foundAny then break end
    if pass < 3 then sleep(0.5) end
  end
end

--- Request a template to be crafted via the crafting turtle.
-- Sends a rednet message or places items for the turtle to craft.
-- @param species Species name for the template
-- @param machines Table from network.scan()
-- @param config BeeOS config
-- @return boolean success
function sampler.requestTemplate(species, machines, config)
  -- Find the gene sample for this species across sample storage chests
  if not inventory.first(config.chests.sampleStorage) then
    tracker.addLog("Cannot craft template: no sample storage configured")
    return false
  end

  local sampleSlot = nil
  local sampleSource = nil

  local sampleMatches = inventory.findAcross(config.chests.sampleStorage, function(meta)
    if not (meta.name or ""):find("gene_sample") then return false end
    -- Match "Bee Sample - Species: <name>"
    local matchedSpecies = bee.normalizeSpecies(
      (meta.displayName or ""):match("Species:%s*(.+)$"))
    return bee.speciesMatch(matchedSpecies, species)
  end)

  if sampleMatches[1] then
    sampleSlot = sampleMatches[1].slot
    sampleSource = sampleMatches[1].source
  end

  if not sampleSlot then
    -- Debug: list all species samples in storage to diagnose mismatches
    local seen = {}
    local found = {}
    inventory.findAcross(config.chests.sampleStorage, function(meta)
      if (meta.name or ""):find("gene_sample") and
         not (meta.name or ""):find("gene_sample_blank") then
        local sp = bee.normalizeSpecies(
          (meta.displayName or ""):match("Species:%s*(.+)$"))
        if sp and not seen[sp] then
          seen[sp] = true
          found[#found + 1] = sp
        end
      end
      return false
    end)
    if #found > 0 then
      tracker.addLog("Cannot craft template: no sample for " .. species
        .. " (have: " .. table.concat(found, ", ") .. ")")
    else
      tracker.addLog("Cannot craft template: no sample for " .. species
        .. " (no species samples in storage)")
    end
    return false
  end

  -- Find a blank template across supply chests
  if not inventory.first(config.chests.supplyInput) then
    tracker.addLog("Cannot craft template: no supply chest configured")
    return false
  end

  local blankSlot = nil
  local blankSource = nil

  local blankMatches = inventory.findAcross(config.chests.supplyInput, function(meta)
    local n = meta.name or ""
    return n:find("gene_template") ~= nil
      and (meta.damage == 0 or meta.displayName == "Genetic Template")
  end)

  if blankMatches[1] then
    blankSlot = blankMatches[1].slot
    blankSource = blankMatches[1].source
  end

  if not blankSlot then
    tracker.addLog("Cannot craft template: no blank templates")
    return false
  end

  -- Send both to crafting turtle
  local turtleName = sampler.findTurtle(config, machines)
  if not turtleName then
    tracker.addLog("Cannot craft template: no turtle found on network")
    return false
  end

  -- Don't push if turtle still has items (avoids duplicate crafts)
  local turtleItems = inventory.listItems(turtleName)
  if #turtleItems > 0 then
    tracker.addLog("Cannot craft template: turtle busy (has items)")
    return false
  end

  -- Push blank template and gene sample to turtle
  local movedBlank = inventory.move(blankSource, blankSlot, turtleName, nil, 1)
  local movedSample = inventory.move(sampleSource, sampleSlot, turtleName, nil, 1)

  if movedBlank > 0 and movedSample > 0 then
    sampler.pendingTemplate = species
    tracker.addLog("Crafting template: " .. species)
    -- Wait for turtle to craft (it polls its own inventory),
    -- then collect the result so we're ready for the next craft
    sleep(2)
    sampler.collectFromTurtle(config, machines)
    return true
  end

  tracker.addLog("Cannot craft template: failed to move items to turtle"
    .. " (blank=" .. movedBlank .. ", sample=" .. movedSample .. ")")
  return false
end

--- Find the crafting turtle on the wired network.
-- Uses config override, then machines table, then peripheral scan.
-- @param config BeeOS config
-- @param machines Optional table from network.scan()
-- @return Peripheral name or nil
function sampler.findTurtle(config, machines)
  if config.turtle.name then
    return config.turtle.name
  end
  -- Check network scan results (already verified as wired peripherals)
  if machines and machines.turtle then
    local name = next(machines.turtle)
    if name then
      -- Cache so callers without machines can still find it
      sampler.cachedTurtle = name
      return name
    end
  end
  -- Fallback: use cached name from previous network scan
  if sampler.cachedTurtle then
    return sampler.cachedTurtle
  end
  return nil
end

--- Collect crafted templates from the turtle's inventory.
-- The turtle crafts items and leaves results in inventory.
-- The computer pulls them out to the template output chest.
-- Learns nbtHash → species mapping for template identification.
-- @param config BeeOS config
-- @param machines Optional table from network.scan()
function sampler.collectFromTurtle(config, machines)
  local turtleName = sampler.findTurtle(config, machines)
  if not turtleName then return end

  if not inventory.first(config.chests.templateOutput) then return end

  local items = inventory.listItems(turtleName)
  for _, item in ipairs(items) do
    -- Learn nbtHash before moving the item
    local itemName = item.meta.name or ""
    if itemName:find("gene_template") and sampler.pendingTemplate then
      local nbtHash = item.meta.nbtHash
      if nbtHash then
        sampler.learnTemplateHash(nbtHash, sampler.pendingTemplate)
      end
    end

    local moved = inventory.moveTo(turtleName, item.slot, config.chests.templateOutput)
    if moved > 0 then
      local species = sampler.pendingTemplate or "unknown"
      tracker.addLog("Collected template: " .. species)
      sampler.pendingTemplate = nil
    end
  end
end

--- Record a template nbtHash → species mapping.
-- @param nbtHash The nbtHash string from getItemMeta
-- @param species The species name
function sampler.learnTemplateHash(nbtHash, species)
  local map = state.load("template_hashes", {})
  if not map[nbtHash] then
    map[nbtHash] = species
    state.save("template_hashes", map)
    tracker.addLog("Learned template hash: " .. species)
  end
end

--- Look up a species from a template's nbtHash.
-- @param nbtHash The nbtHash string
-- @return species name or nil
function sampler.lookupTemplateHash(nbtHash)
  if not nbtHash then return nil end
  local map = state.load("template_hashes", {})
  return map[nbtHash]
end

return sampler
