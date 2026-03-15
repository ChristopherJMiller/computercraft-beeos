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
sampler.pendingTemplate = nil  -- species name of template being crafted

--- Process drones in the buffer: route to sampler or surplus.
-- @param machines Table from network.scan()
-- @param config BeeOS config
function sampler.processDrones(machines, config)
  if not inventory.first(config.chests.droneBuffer) then return end

  local thresholds = config.thresholds

  local allDrones = inventory.findAcross(config.chests.droneBuffer, function(meta)
    return (meta.name or ""):find("bee_drone") ~= nil
  end)

  for _, match in ipairs(allDrones) do
    local bufPeri = peripheral.wrap(match.source)
    if bufPeri and bee.isDrone(bufPeri, match.slot) then
      local info = bee.inspect(bufPeri, match.slot)
      if info and info.species then
        local catalogEntry = tracker.catalog[info.species]
        local sampleCount = catalogEntry and catalogEntry.samples or 0
        local droneCount = catalogEntry and catalogEntry.drones or 0

        if sampleCount < thresholds.minSamplesPerSpecies
            and (sampleCount == 0 or droneCount > thresholds.minDronesPerSpecies) then
          -- Need more samples and have spares — route to sampler
          sampler.sendToSampler(match.source, match.slot, machines, config)
        elseif droneCount > thresholds.maxDronesPerSpecies then
          -- Too many drones — route to surplus/DNA extractor
          local exportChests = inventory.getExportChests(config)
          if inventory.first(exportChests) then
            inventory.moveTo(match.source, match.slot, exportChests)
            tracker.addLog("Surplus drone: " .. info.species .. " -> DNA")
          end
        end
        -- Otherwise leave in buffer (within acceptable range)
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

--- Check sampler output and collect completed samples.
-- @param machines Table from network.scan()
-- @param config BeeOS config
function sampler.collectOutput(machines, config)
  if not inventory.first(config.chests.sampleStorage) then return end

  -- Check all samplers
  local samplers = {}
  if config.machines.samplers then
    for _, name in ipairs(config.machines.samplers) do
      samplers[name] = peripheral.wrap(name)
    end
  else
    samplers = machines.sampler or {}
  end

  for samplerName, samplerPeri in pairs(samplers) do
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
end

--- Request a template to be crafted via the crafting turtle.
-- Sends a rednet message or places items for the turtle to craft.
-- @param species Species name for the template
-- @param machines Table from network.scan()
-- @param config BeeOS config
-- @return boolean success
function sampler.requestTemplate(species, machines, config)
  -- Find the gene sample for this species across sample storage chests
  if not inventory.first(config.chests.sampleStorage) then return false end

  local sampleSlot = nil
  local sampleSource = nil

  local sampleMatches = inventory.findAcross(config.chests.sampleStorage, function(meta)
    if not (meta.name or ""):find("gene_sample") then return false end
    -- Match "Bee Sample - Species: <name>"
    local sampleSpecies = (meta.displayName or ""):match("Species:%s*(.+)$")
    return sampleSpecies == species
  end)

  if sampleMatches[1] then
    sampleSlot = sampleMatches[1].slot
    sampleSource = sampleMatches[1].source
  end

  if not sampleSlot then
    tracker.addLog("Cannot craft template: no sample for " .. species)
    return false
  end

  -- Find a blank template across supply chests
  if not inventory.first(config.chests.supplyInput) then return false end

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
  local turtleName = sampler.findTurtle(config)
  if not turtleName then
    tracker.addLog("Cannot craft template: no crafting turtle found")
    return false
  end

  -- Push blank template and gene sample to turtle
  local movedBlank = inventory.move(blankSource, blankSlot, turtleName, nil, 1)
  local movedSample = inventory.move(sampleSource, sampleSlot, turtleName, nil, 1)

  if movedBlank > 0 and movedSample > 0 then
    -- Turtle polls its inventory and crafts automatically
    sampler.pendingTemplate = species
    tracker.addLog("Crafting template: " .. species)
    return true
  end

  return false
end

--- Find the crafting turtle on the wired network.
-- Uses config override or auto-detects by peripheral name.
-- @param config BeeOS config
-- @return Peripheral name or nil
function sampler.findTurtle(config)
  if config.turtle.name then
    return config.turtle.name
  end
  for _, name in ipairs(peripheral.getNames()) do
    if name:find("turtle") then
      return name
    end
  end
  return nil
end

--- Collect crafted templates from the turtle's inventory.
-- The turtle crafts items and leaves results in inventory.
-- The computer pulls them out to the template output chest.
-- Learns nbtHash → species mapping for template identification.
-- @param config BeeOS config
function sampler.collectFromTurtle(config)
  local turtleName = sampler.findTurtle(config)
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
