-- BeeOS Crafting Turtle
-- Runs on a crafting turtle connected to the wired network.
-- Monitors its inventory for items to craft (blank template + gene sample).
-- When items appear, arranges them in the crafting grid and crafts.

local POLL_INTERVAL = 2  -- seconds

local function log(msg)
  local time = textutils.formatTime(os.time(), true)
  print("[" .. time .. "] " .. msg)
end

--- Count non-empty slots in the turtle's inventory.
local function countItems()
  local count = 0
  for slot = 1, 16 do
    if turtle.getItemCount(slot) > 0 then
      count = count + 1
    end
  end
  return count
end

--- Find items in turtle inventory by name pattern.
local function findItem(pattern)
  for slot = 1, 16 do
    local detail = turtle.getItemDetail(slot)
    if detail and detail.name:find(pattern) then
      return slot, detail
    end
  end
  return nil
end

--- Clear the crafting grid (slots 1-3, 5-7, 9-11 in a crafting turtle).
-- Move any items there to slots 4, 8, 12-16.
local function clearGrid()
  local gridSlots = { 1, 2, 3, 5, 6, 7, 9, 10, 11 }
  local freeSlots = { 4, 8, 12, 13, 14, 15, 16 }

  for _, gs in ipairs(gridSlots) do
    if turtle.getItemCount(gs) > 0 then
      for _, fs in ipairs(freeSlots) do
        if turtle.getItemCount(fs) == 0 then
          turtle.select(gs)
          turtle.transferTo(fs)
          break
        end
      end
    end
  end
end

--- Arrange items for shapeless crafting (2 items).
-- Place them in slots 1 and 2 of the crafting grid.
local function arrangeCraft(slotA, slotB)
  clearGrid()

  -- Move item A to slot 1
  if slotA ~= 1 then
    turtle.select(slotA)
    turtle.transferTo(1)
  end

  -- Move item B to slot 2
  if slotB ~= 2 then
    turtle.select(slotB)
    turtle.transferTo(2)
  end
end

--- Push all items in inventory to adjacent storage (tries all directions).
local function pushResults()
  for slot = 1, 16 do
    if turtle.getItemCount(slot) > 0 then
      turtle.select(slot)
      -- Try dropping in each direction
      if not turtle.drop() then
        if not turtle.dropUp() then
          turtle.dropDown()
        end
      end
    end
  end
end

--- Main crafting loop.
local function main()
  log("BeeOS Crafting Turtle started")
  log("Waiting for items to craft...")

  while true do
    local itemCount = countItems()

    if itemCount >= 2 then
      -- Look for blank template + gene sample combo
      local templateSlot = findItem("gene_template")
      local sampleSlot = findItem("gene_sample")

      if templateSlot and sampleSlot then
        log("Crafting template...")
        arrangeCraft(templateSlot, sampleSlot)

        turtle.select(1)
        local ok = turtle.craft(1)

        if ok then
          log("Template crafted successfully!")
          -- Push result to network or adjacent inventory
          sleep(0.5)
          pushResults()
        else
          log("Craft failed! Check recipe.")
          -- Push items back out so they don't get stuck
          sleep(1)
          pushResults()
        end
      else
        -- Unknown items received, push them back
        log("Unexpected items in inventory, returning...")
        sleep(0.5)
        pushResults()
      end
    end

    sleep(POLL_INTERVAL)
  end
end

main()
