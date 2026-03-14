-- BeeOS Display Manager
-- Renders status information to an Advanced Monitor with touch controls.

local tracker = require("lib.tracker")
local apiary = require("lib.apiary")
local discovery = require("lib.discovery")

local display = {}

-- UI state
display.monitor = nil
display.monitorName = nil
display.scrollOffset = 0
display.activeTab = "species"  -- species, apiaries, discovery, log

-- Layer toggle states (synced from beeos.lua)
display.layerStates = {
  tracker = true,
  apiary = false,
  sampler = false,
  discovery = false,
}

--- Initialize the display.
-- @param config BeeOS config
function display.init(config)
  -- Find monitor
  if config.display.monitorSide then
    display.monitor = peripheral.wrap(config.display.monitorSide)
    display.monitorName = config.display.monitorSide
  else
    -- Auto-detect: find largest monitor
    for _, name in ipairs(peripheral.getNames()) do
      if peripheral.getType(name) == "monitor" then
        display.monitor = peripheral.wrap(name)
        display.monitorName = name
        break
      end
    end
  end

  if display.monitor then
    display.monitor.setTextScale(0.5)
    display.monitor.clear()
  end
end

--- Draw a horizontal line.
local function drawLine(mon, y, w, char)
  mon.setCursorPos(1, y)
  mon.write(string.rep(char or "-", w))
end

--- Draw text at a position with color.
local function drawText(mon, x, y, text, fg, bg)
  mon.setCursorPos(x, y)
  if fg then mon.setTextColor(fg) end
  if bg then mon.setBackgroundColor(bg) end
  mon.write(text)
end

--- Draw the tab bar at the top.
local function drawTabs(mon, w)
  local tabs = {
    { id = "species", label = "Species" },
    { id = "apiaries", label = "Apiaries" },
    { id = "discovery", label = "Discovery" },
    { id = "log", label = "Log" },
  }

  local x = 1
  for _, tab in ipairs(tabs) do
    local active = display.activeTab == tab.id
    local bg = active and colors.blue or colors.gray
    local fg = active and colors.white or colors.lightGray
    local label = " " .. tab.label .. " "

    mon.setCursorPos(x, 1)
    mon.setBackgroundColor(bg)
    mon.setTextColor(fg)
    mon.write(label)
    x = x + #label
  end

  -- Fill rest of line
  mon.setBackgroundColor(colors.black)
  mon.write(string.rep(" ", math.max(0, w - x + 1)))
end

--- Draw layer toggle buttons.
local function drawToggles(mon, w, y)
  local layers = {
    { id = "tracker", label = "Track" },
    { id = "apiary", label = "Apiary" },
    { id = "sampler", label = "Sample" },
    { id = "discovery", label = "Disco" },
  }

  local x = 1
  drawText(mon, x, y, "Layers:", colors.yellow, colors.black)
  x = 9

  for _, layer in ipairs(layers) do
    local on = display.layerStates[layer.id]
    local bg = on and colors.green or colors.red
    local label = " " .. layer.label .. (on and ":ON " or ":OFF")

    mon.setCursorPos(x, y)
    mon.setBackgroundColor(bg)
    mon.setTextColor(colors.white)
    mon.write(label)
    x = x + #label + 1
  end

  mon.setBackgroundColor(colors.black)
end

--- Draw the species catalog tab.
local function drawSpecies(mon, w, h, startY)
  local species = tracker.sortedSpecies()
  local y = startY

  -- Header
  drawText(mon, 1, y, "Species", colors.yellow, colors.black)
  drawText(mon, 20, y, "Samp", colors.yellow)
  drawText(mon, 26, y, "Tmpl", colors.yellow)
  drawText(mon, 32, y, "Drn", colors.yellow)
  drawText(mon, 37, y, "Prnc", colors.yellow)
  y = y + 1
  drawLine(mon, y, w, "-")
  y = y + 1

  -- Species rows
  local maxRows = h - y
  for i = 1 + display.scrollOffset, math.min(#species, maxRows + display.scrollOffset) do
    local sp = species[i]
    if sp and y <= h then
      -- Status indicator
      drawText(mon, 1, y, "*", sp.color, colors.black)
      -- Name (truncated)
      local name = sp.name
      if #name > 17 then name = name:sub(1, 16) .. "~" end
      drawText(mon, 3, y, name, colors.white)
      -- Counts
      drawText(mon, 20, y, string.format("%4d", sp.data.samples),
        sp.data.samples < 3 and colors.orange or colors.white)
      drawText(mon, 26, y, string.format("%4d", sp.data.templates),
        sp.data.templates == 0 and colors.orange or colors.white)
      drawText(mon, 32, y, string.format("%3d", sp.data.drones), colors.lightGray)
      drawText(mon, 37, y, string.format("%3d", sp.data.princesses), colors.lightGray)
      y = y + 1
    end
  end

  -- Footer: total count
  if y <= h then
    drawLine(mon, y, w, "-")
    y = y + 1
    local stats = tracker.stats()
    drawText(mon, 1, y, string.format("Discovered: %d  Stocked: %d  Attention: %d",
      stats.discovered, stats.fullyStocked, stats.needsAttention), colors.lightGray, colors.black)
  end
end

--- Draw the apiaries tab.
local function drawApiaries(mon, w, h, startY)
  local statuses = apiary.getStatuses()
  local y = startY

  drawText(mon, 1, y, "Apiary", colors.yellow, colors.black)
  drawText(mon, 30, y, "Species", colors.yellow)
  drawText(mon, 45, y, "Status", colors.yellow)
  y = y + 1
  drawLine(mon, y, w, "-")
  y = y + 1

  for _, status in ipairs(statuses) do
    if y > h then break end
    -- Name (truncated)
    local name = status.name
    if #name > 27 then name = name:sub(1, 26) .. "~" end
    drawText(mon, 1, y, name, colors.white, colors.black)
    drawText(mon, 30, y, status.species or "None", colors.cyan)

    local stateColor = colors.white
    if status.state == "running" then stateColor = colors.lime
    elseif status.state == "idle" then stateColor = colors.red
    elseif status.state == "restarting" then stateColor = colors.yellow
    end
    drawText(mon, 45, y, status.state, stateColor)
    y = y + 1
  end

  if #statuses == 0 then
    drawText(mon, 1, y, "No apiaries detected", colors.lightGray, colors.black)
  end
end

--- Draw the discovery tab.
local function drawDiscovery(mon, w, h, startY)
  local progress = discovery.getProgress()
  local y = startY

  drawText(mon, 1, y, "Auto-Discovery", colors.yellow, colors.black)
  y = y + 1
  drawLine(mon, y, w, "-")
  y = y + 1

  drawText(mon, 1, y, "Species:  ", colors.lightGray, colors.black)
  drawText(mon, 11, y, string.format("%d / %d discovered",
    progress.discovered, progress.total), colors.white)
  y = y + 1

  drawText(mon, 1, y, "Reachable:", colors.lightGray, colors.black)
  drawText(mon, 11, y, tostring(progress.reachable) .. " species in one step", colors.lime)
  y = y + 1

  drawText(mon, 1, y, "State:    ", colors.lightGray, colors.black)
  local stateColor = progress.state == "idle" and colors.lightGray or colors.yellow
  drawText(mon, 11, y, progress.state, stateColor)
  y = y + 1

  if progress.currentTarget then
    y = y + 1
    drawText(mon, 1, y, "Target: ", colors.lightGray, colors.black)
    drawText(mon, 9, y, progress.currentTarget, colors.cyan)
    y = y + 1

    if progress.currentMutation then
      drawText(mon, 1, y, "Parents:", colors.lightGray, colors.black)
      drawText(mon, 9, y, progress.currentMutation.parent1 .. " + " ..
        progress.currentMutation.parent2, colors.white)
      y = y + 1

      drawText(mon, 1, y, "Chance: ", colors.lightGray, colors.black)
      drawText(mon, 9, y, string.format("%.0f%%", (progress.currentMutation.chance or 0) * 100),
        colors.orange)
      y = y + 1
    end

    drawText(mon, 1, y, "Attempt:", colors.lightGray, colors.black)
    drawText(mon, 9, y, progress.attempts .. " / " .. discovery.maxAttempts, colors.white)
  end

  -- Progress bar
  if progress.total > 0 then
    y = y + 2
    local pct = progress.discovered / progress.total
    local barWidth = w - 2
    local filled = math.floor(pct * barWidth)

    drawText(mon, 1, y, "[", colors.white, colors.black)
    mon.setBackgroundColor(colors.green)
    mon.write(string.rep("=", filled))
    mon.setBackgroundColor(colors.gray)
    mon.write(string.rep(" ", barWidth - filled))
    mon.setBackgroundColor(colors.black)
    mon.write("]")
    y = y + 1
    drawText(mon, 1, y, string.format("%.1f%% complete", pct * 100), colors.lightGray, colors.black)
  end
end

--- Draw the activity log tab.
local function drawLog(mon, w, h, startY)
  local y = startY

  drawText(mon, 1, y, "Activity Log", colors.yellow, colors.black)
  y = y + 1
  drawLine(mon, y, w, "-")
  y = y + 1

  for i = 1 + display.scrollOffset, #tracker.log do
    if y > h then break end
    local entry = tracker.log[i]
    if entry then
      local timeStr = string.format("D%d ", entry.day or 0)
      drawText(mon, 1, y, timeStr, colors.lightGray, colors.black)
      drawText(mon, #timeStr + 1, y, entry.message or "", colors.white)
      y = y + 1
    end
  end

  if #tracker.log == 0 then
    drawText(mon, 1, y, "No activity yet", colors.lightGray, colors.black)
  end
end

--- Render the full display.
function display.render()
  if not display.monitor then return end
  local mon = display.monitor
  local w, h = mon.getSize()

  mon.setBackgroundColor(colors.black)
  mon.clear()

  -- Title bar
  drawText(mon, 1, 1, " BeeOS ", colors.black, colors.yellow)
  local stats = tracker.stats()
  drawText(mon, 9, 1, string.format(" %d species ", stats.discovered), colors.white, colors.black)

  -- Tab bar
  drawTabs(mon, w)

  -- Layer toggles (line 2)
  drawToggles(mon, w, 2)

  -- Content area starts at line 4
  local startY = 4

  if display.activeTab == "species" then
    drawSpecies(mon, w, h, startY)
  elseif display.activeTab == "apiaries" then
    drawApiaries(mon, w, h, startY)
  elseif display.activeTab == "discovery" then
    drawDiscovery(mon, w, h, startY)
  elseif display.activeTab == "log" then
    drawLog(mon, w, h, startY)
  end

  -- Reset colors
  mon.setBackgroundColor(colors.black)
  mon.setTextColor(colors.white)
end

--- Handle a monitor touch event.
-- @param x Touch X coordinate
-- @param y Touch Y coordinate
-- @return Table describing the action, or nil
function display.handleTouch(x, y)
  if not display.monitor then return nil end

  if y == 1 then
    -- Tab selection
    local tabs = { "species", "apiaries", "discovery", "log" }
    local tabWidths = { 9, 10, 11, 5 }  -- " Species ", " Apiaries ", " Discovery ", " Log "
    local tx = 1
    for i, tab in ipairs(tabs) do
      if x >= tx and x < tx + tabWidths[i] then
        display.activeTab = tab
        display.scrollOffset = 0
        return { action = "tab", tab = tab }
      end
      tx = tx + tabWidths[i]
    end
  end

  if y == 2 then
    -- Layer toggles
    -- "Layers: Track:ON  Apiary:OFF Sample:OFF Disco:OFF"
    -- Rough x ranges (these are approximate, depends on rendering)
    local ranges = {
      { 9, 18, "tracker" },
      { 19, 29, "apiary" },
      { 30, 41, "sampler" },
      { 42, 52, "discovery" },
    }
    for _, range in ipairs(ranges) do
      if x >= range[1] and x <= range[2] then
        return { action = "toggle", layer = range[3] }
      end
    end
  end

  return nil
end

return display
