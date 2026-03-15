-- BeeOS Trait Imprinter
-- Checks bee traits against ideal config and routes bees through
-- the Genetic Imprinter to add missing traits before apiary entry.

local bee = require("lib.bee")
local inventory = require("lib.inventory")
local tracker = require("lib.tracker")

local imprinter = {}

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

--- Run one imprinting cycle: check imprinter output, handle waste, start new jobs.
-- @param machines Table from network.scan()
-- @param config BeeOS config
function imprinter.tick(machines, config)
  -- Find an imprinter
  local imprinterName
  if config.machines.imprinters then
    imprinterName = config.machines.imprinters[1]
  else
    imprinterName = next(machines.imprinter or {})
  end

  if not imprinterName then return end

  local imp = peripheral.wrap(imprinterName)
  if not imp then return end

  local size = imp.size and imp.size() or 0

  -- Check output slots for results
  -- Imprinter layout needs Phase 0 verification; scan all slots for output
  for slot = 1, size do
    local meta = imp.getItemMeta and imp.getItemMeta(slot)
    if meta then
      local itemName = meta.name or ""

      if itemName:find("waste") then
        -- Genetic waste — route to export chest
        local exportChests = inventory.getExportChests(config)
        if inventory.first(exportChests) then
          inventory.moveTo(imprinterName, slot, exportChests)
          tracker.addLog("Imprint failed: genetic waste")
        end

      elseif itemName:find("bee_") then
        -- Got a bee back — route princesses to princessStorage, drones to droneBuffer
        local info = bee.inspect(imp, slot)
        if info then
          local isPrincess = itemName:find("bee_princess") or itemName:find("bee_queen")
          local dest = isPrincess and config.chests.princessStorage or config.chests.droneBuffer

          if imprinter.needsImprinting(info, config) then
            -- Still missing traits — re-queue to appropriate buffer
            if inventory.first(dest) then
              inventory.moveTo(imprinterName, slot, dest)
              tracker.addLog("Re-queuing " .. (info.species or "?") ..
                " (still needs: " .. (imprinter.getMissingTrait(info, config) or "?") .. ")")
            end
          else
            -- All traits good — route to appropriate buffer for apiary pickup
            if inventory.first(dest) then
              inventory.moveTo(imprinterName, slot, dest)
              tracker.addLog("Imprinted: " .. (info.species or "?") .. " traits complete")
            end
          end
        end
      end
    end
  end

  -- Look for bees in droneBuffer + princessStorage that need imprinting
  local searchChests = {}
  for _, n in ipairs(inventory.normalize(config.chests.droneBuffer)) do
    searchChests[#searchChests + 1] = n
  end
  for _, n in ipairs(inventory.normalize(config.chests.princessStorage)) do
    searchChests[#searchChests + 1] = n
  end
  if #searchChests == 0 then return end

  local beeMatches = inventory.findAcross(searchChests, function(meta)
    return (meta.name or ""):find("bee_") ~= nil
  end)

  for _, match in ipairs(beeMatches) do
    local bufPeri = peripheral.wrap(match.source)
    if bufPeri then
      local info = bee.inspect(bufPeri, match.slot)
      if info and imprinter.needsImprinting(info, config) then
        local traitName = imprinter.getMissingTrait(info, config)
        if not traitName then break end

        -- Find a template for this trait: traitTemplates first, then supplyInput, sampleStorage
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

        if not templateSlot then
          -- No template available for this trait
          break
        end

        -- Find labware across supply chests
        local labwareSlot = nil
        local labwareSource = nil

        local labwareMatches = inventory.findAcross(config.chests.supplyInput, function(meta)
          return (meta.name or ""):find("labware") ~= nil
        end)
        if labwareMatches[1] then
          labwareSlot = labwareMatches[1].slot
          labwareSource = labwareMatches[1].source
        end

        if not labwareSlot then
          tracker.addLog("Imprinter: no labware available")
          break
        end

        -- Load imprinter: bee + template + labware
        -- Slot assignments need Phase 0 verification (run tools/slots on imprinter)
        local movedBee = inventory.move(match.source, match.slot, imprinterName)
        if movedBee > 0 then
          local movedTpl = inventory.move(templateSource, templateSlot, imprinterName)
          local movedLab = inventory.move(labwareSource, labwareSlot, imprinterName)
          if movedTpl > 0 and movedLab > 0 then
            tracker.addLog("Imprinting " .. (info.species or "?") ..
              ": " .. traitName)
          else
            tracker.addLog("Imprinter: failed to load template/labware" ..
              " (tpl=" .. movedTpl .. ", lab=" .. movedLab .. ")")
          end
        end

        -- Only process one bee per tick to avoid overloading
        break
      end
    end
  end
end

return imprinter
