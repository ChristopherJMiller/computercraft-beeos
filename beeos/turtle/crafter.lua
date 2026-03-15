-- BeeOS Crafting Turtle
-- Runs on a crafting turtle connected to the wired network
-- via an adjacent Wired Modem Full Block.
--
-- The turtle crafts items and drops results into a chest in front.
-- Communicates with the main BeeOS computer via rednet:
--   turtle -> computer: "craft_done" after dropping result
--   computer -> turtle: "status" query, turtle replies "ready"/"busy"

local POLL_INTERVAL = 1  -- seconds
local PROTOCOL = "beeos_turtle"

local busy = false

local function log(msg)
  local time = textutils.formatTime(os.time(), true)
  print("[" .. time .. "] " .. msg)
end

--- Open rednet on any available modem.
-- Checks sides first, then peripheral names for wired modem blocks.
-- @return boolean true if modem found and opened
local function openModem()
  -- Check direct sides (wireless modems, directly attached wired modems)
  for _, side in ipairs(rs.getSides()) do
    if peripheral.getType(side) == "modem" then
      rednet.open(side)
      return true
    end
  end
  -- Check peripheral names (wired modem full blocks placed adjacent)
  for _, name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name) == "modem" then
      rednet.open(name)
      return true
    end
  end
  return false
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

--- Drop all items into the chest in front.
local function dropAll()
  for slot = 1, 16 do
    if turtle.getItemCount(slot) > 0 then
      turtle.select(slot)
      turtle.drop()
    end
  end
end

--- Crafting loop coroutine.
local function craftLoop()
  while true do
    local itemCount = countItems()

    if itemCount >= 2 then
      busy = true
      -- Look for blank template + gene sample combo
      local templateSlot = findItem("gene_template")
      local sampleSlot = findItem("gene_sample")

      if templateSlot and sampleSlot then
        log("Crafting template...")
        arrangeCraft(templateSlot, sampleSlot)

        turtle.select(1)
        local ok = turtle.craft(1)

        if ok then
          log("Template crafted, dropping into chest...")
          dropAll()
          busy = false
          rednet.broadcast("craft_done", PROTOCOL)
          log("Notified computer: craft_done")
        else
          log("Craft failed! Dropping items back...")
          dropAll()
          busy = false
          rednet.broadcast("craft_failed", PROTOCOL)
        end
      else
        -- Items present but not a valid combo, drop them back
        log("Invalid items in inventory, dropping...")
        dropAll()
        busy = false
      end
    end

    sleep(POLL_INTERVAL)
  end
end

--- Rednet listener coroutine.
-- Handles "stop" and "status" messages.
local function rednetListener()
  while true do
    local senderId, message = rednet.receive(PROTOCOL)
    if message == "stop" then
      log("Stop signal from computer #" .. tostring(senderId))
      return
    elseif message == "status" then
      local state = busy and "busy" or "ready"
      rednet.send(senderId, state, PROTOCOL)
    end
  end
end

--- Terminal input coroutine.
local function terminalListener()
  while true do
    write("crafter> ")
    local input = read()
    if input then
      local cmd = input:match("^%s*(%S+)")
      if cmd == "stop" or cmd == "quit" or cmd == "exit" then
        log("Stop command received from terminal")
        return
      elseif cmd == "status" then
        local state = busy and "busy" or "ready"
        log("Status: " .. state .. ", items: " .. countItems())
      elseif cmd == "help" then
        print("Commands: status, stop, help")
      elseif cmd and cmd ~= "" then
        print("Unknown command. Type 'help'.")
      end
    end
  end
end

--- Check for an inventory in front of the turtle.
-- @return boolean
local function hasOutputChest()
  local front = peripheral.wrap("front")
  return front ~= nil and front.size ~= nil
end

--- Main entry point.
local function main()
  log("BeeOS Crafting Turtle started")

  if not hasOutputChest() then
    log("ERROR: No inventory found in front of turtle!")
    log("Place a chest in front of the turtle for template output.")
    return
  end
  log("Output chest detected")

  local modemOk = openModem()
  if modemOk then
    log("Rednet open (ID: " .. os.getComputerID() .. ")")
    rednet.host(PROTOCOL, "beeos_crafter")
  else
    log("ERROR: No modem found, cannot communicate with computer")
    return
  end

  log("Waiting for items to craft...")
  log("Type 'stop' to exit")

  parallel.waitForAny(craftLoop, rednetListener, terminalListener)

  log("BeeOS Crafting Turtle stopped.")
end

main()
