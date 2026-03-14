-- BeeOS Inventory Manager
-- Helpers for moving items between peripherals on the wired network.

local inventory = {}

--- Move items from one peripheral slot to another.
-- Uses pushItems from the source peripheral.
-- @param fromName Source peripheral name
-- @param fromSlot Source slot number
-- @param toName Destination peripheral name
-- @param toSlot Destination slot number (optional)
-- @param limit Max items to move (optional)
-- @return Number of items moved
function inventory.move(fromName, fromSlot, toName, toSlot, limit)
  local from = peripheral.wrap(fromName)
  if not from then
    error("Source peripheral not found: " .. fromName)
  end
  return from.pushItems(toName, fromSlot, limit, toSlot)
end

--- Pull items from a source into a destination.
-- Uses pullItems from the destination peripheral.
-- @param toName Destination peripheral name
-- @param toSlot Destination slot (optional)
-- @param fromName Source peripheral name
-- @param fromSlot Source slot number
-- @param limit Max items to pull (optional)
-- @return Number of items moved
function inventory.pull(toName, toSlot, fromName, fromSlot, limit)
  local to = peripheral.wrap(toName)
  if not to then
    error("Destination peripheral not found: " .. toName)
  end
  return to.pullItems(fromName, fromSlot, limit, toSlot)
end

--- Find all slots matching a predicate in an inventory.
-- @param periName Peripheral name
-- @param predicate function(meta) -> boolean
-- @return List of { slot=n, meta=table }
function inventory.findSlots(periName, predicate)
  local p = peripheral.wrap(periName)
  if not p then return {} end

  local results = {}
  local size = p.size and p.size() or 0

  for slot = 1, size do
    local meta = p.getItemMeta and p.getItemMeta(slot) or p.getItemDetail and p.getItemDetail(slot)
    if meta and predicate(meta) then
      results[#results + 1] = { slot = slot, meta = meta }
    end
  end

  return results
end

--- Find the first empty slot in an inventory.
-- @param periName Peripheral name
-- @return Slot number or nil
function inventory.findEmpty(periName)
  local p = peripheral.wrap(periName)
  if not p then return nil end

  local size = p.size and p.size() or 0
  for slot = 1, size do
    local meta = p.getItemMeta and p.getItemMeta(slot) or p.getItemDetail and p.getItemDetail(slot)
    if not meta then
      return slot
    end
  end

  return nil
end

--- Count items matching a predicate across multiple inventories.
-- @param periNames List of peripheral names
-- @param predicate function(meta) -> boolean
-- @return Total count
function inventory.countAcross(periNames, predicate)
  local total = 0
  for _, name in ipairs(periNames) do
    local matches = inventory.findSlots(name, predicate)
    for _, match in ipairs(matches) do
      total = total + (match.meta.count or 1)
    end
  end
  return total
end

--- Move all items matching a predicate from one inventory to another.
-- @param fromName Source peripheral name
-- @param toName Destination peripheral name
-- @param predicate function(meta) -> boolean
-- @return Number of items moved total
function inventory.moveMatching(fromName, toName, predicate)
  local matches = inventory.findSlots(fromName, predicate)
  local total = 0
  for _, match in ipairs(matches) do
    local moved = inventory.move(fromName, match.slot, toName)
    total = total + moved
  end
  return total
end

--- List all non-empty slots in an inventory.
-- @param periName Peripheral name
-- @return List of { slot=n, meta=table }
function inventory.listItems(periName)
  return inventory.findSlots(periName, function() return true end)
end

--- Check if an inventory has any empty slots.
-- @param periName Peripheral name
-- @return boolean
function inventory.hasSpace(periName)
  return inventory.findEmpty(periName) ~= nil
end

--- Get the total number of slots in an inventory.
-- @param periName Peripheral name
-- @return Number of slots, or 0
function inventory.size(periName)
  local p = peripheral.wrap(periName)
  if not p then return 0 end
  return p.size and p.size() or 0
end

return inventory
