-- BeeOS Trait Imprinter
-- Checks bee traits against ideal config and routes bees through
-- the Genetic Imprinter to add missing traits before apiary entry.

local bee = require("lib.bee")
local inventory = require("lib.inventory")
local tracker = require("lib.tracker")

local imprinter = {}

-- Activity tracking: { [machineName] = speciesName }
imprinter.activeSpecies = {}

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

--- Run one imprinting cycle across all available imprinters.
-- @param machines Table from network.scan()
-- @param config BeeOS config
function imprinter.tick(machines, config)
  -- Build list of all imprinters
  local imprinters = {}
  if config.machines.imprinters then
    for _, name in ipairs(config.machines.imprinters) do
      imprinters[name] = peripheral.wrap(name)
    end
  else
    imprinters = machines.imprinter or {}
  end

  if not next(imprinters) then return end

  -- Phase 1: Collect output from all imprinters, find idle ones
  local idleImprinters = {}

  for impName, imp in pairs(imprinters) do
    if imp then
      local idle = imprinter.collectOutput(impName, imp, config)
      if idle then
        idleImprinters[#idleImprinters + 1] = impName
        imprinter.activeSpecies[impName] = nil
      end
    end
  end

  if #idleImprinters == 0 then return end

  -- Phase 2: Load bees into idle imprinters
  local searchChests = {}
  for _, n in ipairs(inventory.normalize(config.chests.droneBuffer)) do
    searchChests[#searchChests + 1] = n
  end
  for _, n in ipairs(inventory.normalize(config.chests.princessStorage)) do
    searchChests[#searchChests + 1] = n
  end
  if #searchChests == 0 then return end

  local beeMatches = inventory.findAcross(searchChests, function(m)
    return (m.name or ""):find("bee_") ~= nil
  end)

  local beeIdx = 1
  for _, impName in ipairs(idleImprinters) do
    -- Try to find the next bee that needs imprinting
    while beeIdx <= #beeMatches do
      local match = beeMatches[beeIdx]
      beeIdx = beeIdx + 1

      local bufPeri = peripheral.wrap(match.source)
      if bufPeri then
        local info = bee.inspect(bufPeri, match.slot)
        if info and info.analyzed ~= false and imprinter.needsImprinting(info, config) then
          local traitName = imprinter.getMissingTrait(info, config)
          if not traitName then break end

          -- Find a template for this trait
          local templateSlot = nil
          local templateSource = nil

          local templateChests = {}
          for _, n in ipairs(inventory.normalize(config.chests.traitTemplates)) do
            templateChests[#templateChests + 1] = n
          end
          for _, n in ipairs(inventory.normalize(config.chests.supplyInput)) do
            templateChests[#templateChests + 1] = n
          end
          for _, n in ipairs(inventory.normalize(config.chests.sampleStorage)) do
            templateChests[#templateChests + 1] = n
          end

          for _, chestName in ipairs(templateChests) do
            templateSlot = imprinter.findTraitTemplate(chestName, traitName)
            if templateSlot then
              templateSource = chestName
              break
            end
          end

          if not templateSlot then break end

          -- Find labware
          local labwareMatches = inventory.findAcross(config.chests.supplyInput, function(m)
            return (m.name or ""):find("labware") ~= nil
          end)
          if not labwareMatches[1] then
            tracker.addLog("Imprinter: no labware available")
            return  -- No labware = can't load any imprinter
          end

          -- Load imprinter: bee + template + labware
          local movedBee = inventory.move(match.source, match.slot, impName)
          if movedBee > 0 then
            local movedTpl = inventory.move(templateSource, templateSlot, impName)
            local movedLab = inventory.move(
              labwareMatches[1].source, labwareMatches[1].slot, impName)
            if movedTpl > 0 and movedLab > 0 then
              imprinter.activeSpecies[impName] = info.species or "?"
              tracker.addLog("Imprinting " .. (info.species or "?") ..
                ": " .. traitName .. " (" .. impName .. ")")
            else
              tracker.addLog("Imprinter: failed to load template/labware" ..
                " (tpl=" .. movedTpl .. ", lab=" .. movedLab .. ")")
            end
            break  -- This imprinter is loaded, move to next idle one
          end
        end
      end
    end
  end
end

return imprinter
