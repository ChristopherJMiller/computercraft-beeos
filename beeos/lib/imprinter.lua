-- BeeOS Trait Imprinter
-- Checks bee traits against ideal config and routes bees through
-- the Genetic Imprinter to add missing traits before apiary entry.

local bee = require("lib.bee")
local inventory = require("lib.inventory")
local tracker = require("lib.tracker")

local imprinter = {}

-- Activity tracking: { [machineName] = speciesName }
imprinter.activeSpecies = {}
-- Track which imprinters have trait templates loaded (vs species templates)
imprinter.hasTraitTemplate = {}

--- Check if a bee needs imprinting based on config.traits.
-- @param beeInfo Table returned by bee.inspect()
-- @param config BeeOS config
-- @return boolean
function imprinter.needsImprinting(beeInfo, config)
  if not config.traits then return false end
  if not beeInfo then return false end
  local t = config.traits
  if t.caveDwelling and not beeInfo.caveDwelling then return true end
  if t.neverSleeps and not beeInfo.neverSleeps then return true end
  if t.toleratesRain and not beeInfo.toleratesRain then return true end
  return false
end

--- Get the first missing trait that needs imprinting.
-- Returns one at a time since the Genetic Imprinter does one template per op.
-- @param beeInfo Table returned by bee.inspect()
-- @param config BeeOS config
-- @return string trait name for template matching, or nil
function imprinter.getMissingTrait(beeInfo, config)
  if not config.traits then return nil end
  if not beeInfo then return nil end
  local t = config.traits
  if t.caveDwelling and not beeInfo.caveDwelling then return "Cave Dwelling" end
  if t.neverSleeps and not beeInfo.neverSleeps then return "Never Sleeps" end
  if t.toleratesRain and not beeInfo.toleratesRain then return "Tolerates Rain" end
  return nil
end

--- Find a trait template in an inventory by matching displayName.
-- @param periName Peripheral name
-- @param traitName Trait string to search for (e.g. "Cave Dwelling")
-- @return slot number or nil
function imprinter.findTraitTemplate(periName, traitName)
  local peri = peripheral.wrap(periName)
  if not peri then return nil end
  local size = peri.size and peri.size() or 0
  for slot = 1, size do
    local meta = peri.getItemMeta and peri.getItemMeta(slot)
    if meta and (meta.name or ""):find("gene_template") then
      if (meta.displayName or ""):find(traitName) then
        return slot
      end
    end
  end
  return nil
end

--- Collect output from a single imprinter. Returns true if imprinter is now idle.
-- @param impName Peripheral name
-- @param imp Wrapped peripheral
-- @param config BeeOS config
-- @return boolean idle
function imprinter.collectOutput(impName, imp, config)
  local size = imp.size and imp.size() or 0
  local hasItems = false

  for slot = 1, size do
    local meta = imp.getItemMeta and imp.getItemMeta(slot)
    if meta then
      local itemName = meta.name or ""
      local moved = false

      if itemName:find("waste") then
        local exportChests = inventory.getExportChests(config)
        if inventory.first(exportChests) then
          inventory.moveTo(impName, slot, exportChests)
          tracker.addLog("Imprint failed: genetic waste")
          moved = true
        end

      elseif itemName:find("gene_template") then
        -- Route trait templates back to traitTemplates, species templates to templateOutput
        local dest = imprinter.hasTraitTemplate[impName]
          and config.chests.traitTemplates or config.chests.templateOutput
        if inventory.first(dest) then
          inventory.moveTo(impName, slot, dest)
          moved = true
        end

      elseif itemName:find("bee_") then
        local info = bee.inspect(imp, slot)
        if info then
          local isPrincess = itemName:find("bee_princess") or itemName:find("bee_queen")
          local dest = isPrincess and config.chests.princessStorage or config.chests.droneBuffer

          if imprinter.needsImprinting(info, config) then
            if inventory.first(dest) then
              inventory.moveTo(impName, slot, dest)
              tracker.addLog("Re-queuing " .. (info.species or "?") ..
                " (still needs: " .. (imprinter.getMissingTrait(info, config) or "?") .. ")")
              moved = true
            end
          else
            if inventory.first(dest) then
              inventory.moveTo(impName, slot, dest)
              tracker.addLog("Imprinted: " .. (info.species or "?") .. " traits complete")
              moved = true
            end
          end
        end
      end

      if not moved then hasItems = true end
    end
  end

  return not hasItems
end

--- Get all available imprinters (config override or auto-detected).
-- @param machines Table from network.scan()
-- @param config BeeOS config
-- @return Table of { [name] = wrappedPeripheral }
function imprinter.getImprinters(machines, config)
  local imprinters = {}
  if config.machines.imprinters then
    for _, name in ipairs(config.machines.imprinters) do
      imprinters[name] = peripheral.wrap(name)
    end
  else
    imprinters = machines.imprinter or {}
  end
  return imprinters
end

--- Find the apiary-ready template in the traitTemplates chest.
-- @param config BeeOS config
-- @return chestName, slot or nil, nil
function imprinter.findApiaryTemplate(config)
  if not config.chests.traitTemplates then return nil, nil end
  local chests = inventory.normalize(config.chests.traitTemplates)
  for _, chestName in ipairs(chests) do
    local peri = peripheral.wrap(chestName)
    if peri then
      local size = peri.size and peri.size() or 0
      for slot = 1, size do
        local meta = peri.getItemMeta and peri.getItemMeta(slot)
        if meta and (meta.name or ""):find("gene_template")
            and meta.nbtHash ~= nil then
          return chestName, slot
        end
      end
    end
  end
  return nil, nil
end

--- Send a bee to an idle imprinter with the apiary-ready template.
-- Called by apiary layer when a bee needs traits before entering an apiary.
-- @param beeSource Peripheral name where bee is
-- @param beeSlot Slot number
-- @param machines Table from network.scan()
-- @param config BeeOS config
-- @return boolean success
function imprinter.sendToImprinter(beeSource, beeSlot, machines, config)
  local imprinters = imprinter.getImprinters(machines, config)
  if not next(imprinters) then return false end

  -- Find an idle imprinter
  local impName = nil
  for name, imp in pairs(imprinters) do
    if imp and not imprinter.activeSpecies[name] then
      -- Check if it's actually empty
      local idle = imprinter.collectOutput(name, imp, config)
      if idle then
        impName = name
        break
      end
    end
  end
  if not impName then return false end

  -- Find apiary-ready template
  local tplSource, tplSlot = imprinter.findApiaryTemplate(config)
  if not tplSource then
    tracker.addLog("Apiary prep: no apiary-ready template in traitTemplates")
    return false
  end

  -- Find labware
  local labwareMatches = inventory.findAcross(
    config.chests.supplyInput, function(m)
      return (m.name or ""):find("labware") ~= nil
    end)
  if not labwareMatches[1] then
    tracker.addLog("Apiary prep: no labware available")
    return false
  end

  -- Inspect bee for logging
  local bufPeri = peripheral.wrap(beeSource)
  local species = "?"
  if bufPeri then
    local info = bee.inspect(bufPeri, beeSlot)
    if info then species = info.species or "?" end
  end

  -- Load imprinter: bee + template + labware
  local movedBee = inventory.move(beeSource, beeSlot, impName)
  if movedBee > 0 then
    local movedTpl = inventory.move(tplSource, tplSlot, impName)
    local movedLab = inventory.move(
      labwareMatches[1].source, labwareMatches[1].slot, impName)
    if movedTpl > 0 and movedLab > 0 then
      imprinter.activeSpecies[impName] = species
      imprinter.hasTraitTemplate[impName] = true
      tracker.addLog("Apiary prep: imprinting " .. species
        .. " (" .. impName .. ")")
      return true
    else
      tracker.addLog("Apiary prep: failed to load template/labware"
        .. " (tpl=" .. movedTpl .. ", lab=" .. movedLab .. ")")
    end
  end
  return false
end

--- Collect output from all imprinters.
-- @param machines Table from network.scan()
-- @param config BeeOS config
function imprinter.tick(machines, config)
  local imprinters = imprinter.getImprinters(machines, config)
  if not next(imprinters) then return end

  for impName, imp in pairs(imprinters) do
    if imp then
      local idle = imprinter.collectOutput(impName, imp, config)
      if idle then
        imprinter.activeSpecies[impName] = nil
        imprinter.hasTraitTemplate[impName] = nil
      end
    end
  end
end

--- Poll active imprinters for output, collecting as soon as ready.
-- Replaces idle sleep() at end of imprinter loop for faster output pickup.
-- @param machines Table from network.scan()
-- @param config BeeOS config
-- @param duration Max seconds to poll before returning
function imprinter.pollActive(machines, config, duration)
  if not next(imprinter.activeSpecies) then
    sleep(duration)
    return
  end

  local imprinters = {}
  if config.machines.imprinters then
    for _, name in ipairs(config.machines.imprinters) do
      imprinters[name] = peripheral.wrap(name)
    end
  else
    imprinters = machines.imprinter or {}
  end

  local deadline = os.clock() + duration
  while os.clock() < deadline do
    sleep(0.5)

    local allIdle = true
    for impName, imp in pairs(imprinters) do
      if imp and imprinter.activeSpecies[impName] then
        local idle = imprinter.collectOutput(impName, imp, config)
        if idle then
          imprinter.activeSpecies[impName] = nil
          imprinter.hasTraitTemplate[impName] = nil
        else
          allIdle = false
        end
      end
    end

    if allIdle then return end
  end
end

return imprinter
