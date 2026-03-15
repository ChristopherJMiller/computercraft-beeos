-- BeeOS Trait Imprinter
-- Checks bee traits against ideal config and routes bees through
-- the Genetic Imprinter to add missing traits before apiary entry.

local bee = require("lib.bee")
local inventory = require("lib.inventory")
local tracker = require("lib.tracker")

local imprinter = {}

--- Get the export chest name with backwards-compatible fallback.
-- @param config BeeOS config
-- @return Peripheral name or nil
local function getExportChest(config)
  return config.chests.export
    or config.chests.productOutput
    or config.chests.surplusOutput
end

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
        local exportChest = getExportChest(config)
        if exportChest then
          inventory.move(imprinterName, slot, exportChest)
          tracker.addLog("Imprint failed: genetic waste")
        end

      elseif itemName:find("bee_") then
        -- Got a bee back — check if it still needs traits
        local info = bee.inspect(imp, slot)
        if info then
          if imprinter.needsImprinting(info, config) then
            -- Still missing traits — leave in imprinter for next cycle
            -- or move to drone buffer for re-routing
            local droneBuffer = config.chests.droneBuffer
            if droneBuffer then
              inventory.move(imprinterName, slot, droneBuffer)
              tracker.addLog("Re-queuing " .. (info.species or "?") ..
                " (still needs: " .. (imprinter.getMissingTrait(info, config) or "?") .. ")")
            end
          else
            -- All traits good — send to drone buffer for apiary routing
            local droneBuffer = config.chests.droneBuffer
            if droneBuffer then
              inventory.move(imprinterName, slot, droneBuffer)
              tracker.addLog("Imprinted: " .. (info.species or "?") .. " traits complete")
            end
          end
        end
      end
    end
  end

  -- Look for bees in drone buffer that need imprinting
  local droneBuffer = config.chests.droneBuffer
  if not droneBuffer then return end

  local bufferPeri = peripheral.wrap(droneBuffer)
  if not bufferPeri then return end
  local bufferSize = bufferPeri.size and bufferPeri.size() or 0

  for slot = 1, bufferSize do
    local meta = bufferPeri.getItemMeta and bufferPeri.getItemMeta(slot)
    if meta and (meta.name or ""):find("bee_") then
      local info = bee.inspect(bufferPeri, slot)
      if info and imprinter.needsImprinting(info, config) then
        local traitName = imprinter.getMissingTrait(info, config)
        if not traitName then break end

        -- Find a template for this trait
        local templateSlot = nil
        local templateSource = nil

        -- Check supply input first
        if config.chests.supplyInput then
          templateSlot = imprinter.findTraitTemplate(config.chests.supplyInput, traitName)
          if templateSlot then templateSource = config.chests.supplyInput end
        end

        -- Check sample storage
        if not templateSlot and config.chests.sampleStorage then
          templateSlot = imprinter.findTraitTemplate(config.chests.sampleStorage, traitName)
          if templateSlot then templateSource = config.chests.sampleStorage end
        end

        if not templateSlot then
          -- No template available for this trait
          break
        end

        -- Find labware in supply chest
        local labwareSlot = nil
        if config.chests.supplyInput then
          local supplyPeri = peripheral.wrap(config.chests.supplyInput)
          if supplyPeri then
            local supplySize = supplyPeri.size and supplyPeri.size() or 0
            for s = 1, supplySize do
              if bee.isLabware(supplyPeri, s) then
                labwareSlot = s
                break
              end
            end
          end
        end

        if not labwareSlot then
          tracker.addLog("Imprinter: no labware available")
          break
        end

        -- Load imprinter: bee + template + labware
        -- Slot assignments need Phase 0 verification
        local movedBee = inventory.move(droneBuffer, slot, imprinterName)
        if movedBee > 0 then
          inventory.move(templateSource, templateSlot, imprinterName)
          inventory.move(config.chests.supplyInput, labwareSlot, imprinterName)
          tracker.addLog("Imprinting " .. (info.species or "?") ..
            ": " .. traitName)
        end

        -- Only process one bee per tick to avoid overloading
        break
      end
    end
  end
end

return imprinter
