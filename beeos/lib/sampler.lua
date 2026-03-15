-- BeeOS Layer 2: Sample & Template Manager
-- Manages genetic sampling of drones and template crafting.

local bee = require("lib.bee")
local inventory = require("lib.inventory")
local tracker = require("lib.tracker")

local sampler = {}

-- Current state
sampler.state = "idle"  -- idle, sampling, waiting_output
sampler.currentSpecies = nil

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
            and droneCount > thresholds.minDronesPerSpecies then
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
  -- Find an available sampler
  local samplerName
  if config.machines.samplers then
    samplerName = config.machines.samplers[1]
  else
    samplerName = next(machines.sampler or {})
  end

  if not samplerName then return false end

  -- Check sampler isn't busy (has items in output)
  -- Slot layout needs Phase 0 verification:
  -- Typically: input bee slot, labware slot, blank sample slot, output slot

  -- Ensure labware is available
  sampler.ensureLabware(samplerName, machines, config)

  -- Ensure blank gene samples are available
  sampler.ensureBlankSamples(samplerName, machines, config)

  -- Send the drone
  local moved = inventory.move(fromPeri, fromSlot, samplerName)
  if moved > 0 then
    local info = bee.inspect(peripheral.wrap(fromPeri), fromSlot)
    sampler.state = "sampling"
    sampler.currentSpecies = info and info.species or "Unknown"
    tracker.addLog("Sampling: " .. (sampler.currentSpecies or "?"))
    return true
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
    for slot = 1, size do
      local meta = samplerPeri.getItemMeta and samplerPeri.getItemMeta(slot)
      if meta then
        local itemName = meta.name or ""
        if itemName:find("gene_sample") then
          -- Completed gene sample → sample storage
          local moved = inventory.moveTo(samplerName, slot, config.chests.sampleStorage)
          if moved > 0 then
            sampler.state = "idle"
            sampler.currentSpecies = nil
            tracker.addLog("Sample collected -> storage")
          end
        elseif itemName:find("bee_drone") then
          -- Spent drone returned by sampler → drone buffer
          if inventory.first(config.chests.droneBuffer) then
            inventory.moveTo(samplerName, slot, config.chests.droneBuffer)
          end
        elseif itemName:find("bee_") then
          -- Any other bee output → drone buffer
          if inventory.first(config.chests.droneBuffer) then
            inventory.moveTo(samplerName, slot, config.chests.droneBuffer)
          end
        elseif itemName:find("waste") then
          -- Genetic waste → export
          local exportChests = inventory.getExportChests(config)
          if inventory.first(exportChests) then
            inventory.moveTo(samplerName, slot, exportChests)
          end
        end
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
    return (meta.displayName or ""):find(species) ~= nil
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
-- @param config BeeOS config
function sampler.collectFromTurtle(config)
  local turtleName = sampler.findTurtle(config)
  if not turtleName then return end

  if not inventory.first(config.chests.templateOutput) then return end

  local items = inventory.listItems(turtleName)
  for _, item in ipairs(items) do
    local moved = inventory.moveTo(turtleName, item.slot, config.chests.templateOutput)
    if moved > 0 then
      tracker.addLog("Collected template from turtle")
    end
  end
end

return sampler
