-- BeeOS Crafting Turtle
-- Runs on a crafting turtle connected to the wired network
-- via an adjacent Wired Modem Full Block.
--
-- The turtle is a dumb crafter: it monitors its inventory for items,
-- arranges them in the crafting grid, and crafts. Results stay in
-- inventory for the computer to pull out via the network.

local POLL_INTERVAL = 2  -- seconds
local PROTOCOL = "beeos"

local function log(msg)
  local time = textutils.formatTime(os.time(), true)
  print("[" .. time .. "] " .. msg)
end

--- Open rednet on the wired modem.
-- Finds the modem side automatically.
-- @return boolean true if modem found and opened
local function openModem()
  for _, side in ipairs(rs.getSides()) do
    if peripheral.getType(side) == "modem" then
      rednet.open(side)
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

--- Crafting loop coroutine.
local function craftLoop()
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
          log("Template crafted! Waiting for computer to collect...")
        else
          log("Craft failed! Check recipe.")
        end
      end
      -- Items stay in inventory; computer pulls them out via network
    end

    sleep(POLL_INTERVAL)
  end
end

--- Rednet listener coroutine.
-- Listens for "stop" messages on the "beeos" protocol.
local function rednetListener()
  while true do
    local senderId, message = rednet.receive(PROTOCOL)
    if message == "stop" then
      log("Stop signal received from computer #" .. tostring(senderId))
      return
    end
  end
end

--- Terminal input coroutine.
-- Accepts "stop", "quit", or "exit" typed at the turtle's terminal.
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
        log("Crafting turtle running. Items in inventory: " .. countItems())
      elseif cmd == "help" then
        print("Commands: status, stop, help")
      elseif cmd and cmd ~= "" then
        print("Unknown command. Type 'help'.")
      end
    end
  end
end

--- Main entry point.
local function main()
  log("BeeOS Crafting Turtle started")

  local modemOk = openModem()
  if modemOk then
    log("Rednet open (ID: " .. os.getComputerID() .. ")")
  else
    log("WARNING: No modem found, remote stop unavailable")
  end

  log("Waiting for items to craft...")
  log("Type 'stop' to exit")

  if modemOk then
    parallel.waitForAny(craftLoop, rednetListener, terminalListener)
  else
    parallel.waitForAny(craftLoop, terminalListener)
  end

  log("BeeOS Crafting Turtle stopped.")
end

main()
