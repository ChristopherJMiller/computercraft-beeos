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
  local droneBuffer = config.chests.droneBuffer
  if not droneBuffer then return end

  local bufferPeri = peripheral.wrap(droneBuffer)
  if not bufferPeri then return end

  local bufferSize = bufferPeri.size and bufferPeri.size() or 0
  local thresholds = config.thresholds

  for slot = 1, bufferSize do
    if bee.isDrone(bufferPeri, slot) then
      local info = bee.inspect(bufferPeri, slot)
      if info and info.species then
        local catalogEntry = tracker.catalog[info.species]
        local sampleCount = catalogEntry and catalogEntry.samples or 0
        local droneCount = catalogEntry and catalogEntry.drones or 0

        if sampleCount < thresholds.minSamplesPerSpecies then
          -- Need more samples — route to sampler
          sampler.sendToSampler(droneBuffer, slot, machines, config)
        elseif droneCount > thresholds.maxDronesPerSpecies then
          -- Too many drones — route to surplus/DNA extractor
          if config.chests.surplusOutput then
            inventory.move(droneBuffer, slot, config.chests.surplusOutput)
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
  local supplyChest = config.chests.supplyInput
  if not supplyChest then return end

  local supplyPeri = peripheral.wrap(supplyChest)
  if not supplyPeri then return end

  local supplySize = supplyPeri.size and supplyPeri.size() or 0
  for slot = 1, supplySize do
    if bee.isLabware(supplyPeri, slot) then
      inventory.move(supplyChest, slot, samplerName, nil, 1)
      return
    end
  end
end

--- Ensure blank gene samples are in the sampler.
function sampler.ensureBlankSamples(samplerName, machines, config)
  local supplyChest = config.chests.supplyInput
  if not supplyChest then return end

  local supplyPeri = peripheral.wrap(supplyChest)
  if not supplyPeri then return end

  local supplySize = supplyPeri.size and supplyPeri.size() or 0
  for slot = 1, supplySize do
    local meta = supplyPeri.getItemMeta and supplyPeri.getItemMeta(slot)
    if meta and (meta.name or ""):find("gene_sample_blank") then
      inventory.move(supplyChest, slot, samplerName, nil, 1)
      return
    end
  end
end

--- Check sampler output and collect completed samples.
-- @param machines Table from network.scan()
-- @param config BeeOS config
function sampler.collectOutput(machines, config)
  local sampleStorage = config.chests.sampleStorage
  if not sampleStorage then return end

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
      if bee.isGeneSample(samplerPeri, slot) then
        local moved = inventory.move(samplerName, slot, sampleStorage)
        if moved > 0 then
          sampler.state = "idle"
          sampler.currentSpecies = nil
          tracker.addLog("Sample collected -> storage")
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
  -- Find the gene sample for this species in sample storage
  local sampleStorage = config.chests.sampleStorage
  if not sampleStorage then return false end

  local storagePeri = peripheral.wrap(sampleStorage)
  if not storagePeri then return false end

  local sampleSlot = nil
  local storageSize = storagePeri.size and storagePeri.size() or 0

  for slot = 1, storageSize do
    if bee.isGeneSample(storagePeri, slot) then
      local meta = storagePeri.getItemMeta(slot)
      if meta and (meta.displayName or ""):find(species) then
        sampleSlot = slot
        break
      end
    end
  end

  if not sampleSlot then
    tracker.addLog("Cannot craft template: no sample for " .. species)
    return false
  end

  -- Find a blank template in supply chest
  local supplyChest = config.chests.supplyInput
  if not supplyChest then return false end

  local supplyPeri = peripheral.wrap(supplyChest)
  if not supplyPeri then return false end

  local blankSlot = nil
  local supplySize = supplyPeri.size and supplyPeri.size() or 0
  for slot = 1, supplySize do
    if bee.isBlankTemplate(supplyPeri, slot) then
      blankSlot = slot
      break
    end
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
  local movedBlank = inventory.move(supplyChest, blankSlot, turtleName, nil, 1)
  local movedSample = inventory.move(sampleStorage, sampleSlot, turtleName, nil, 1)

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

  local outputChest = config.chests.templateOutput
  if not outputChest then return end

  local items = inventory.listItems(turtleName)
  for _, item in ipairs(items) do
    local moved = inventory.move(turtleName, item.slot, outputChest)
    if moved > 0 then
      tracker.addLog("Collected template from turtle")
    end
  end
end

return sampler
