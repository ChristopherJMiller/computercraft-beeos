-- BeeOS Display Manager
-- Renders status information to an Advanced Monitor with touch controls.

local tracker = require("lib.tracker")
local apiary = require("lib.apiary")
local discovery = require("lib.discovery")
local state = require("lib.state")

local display = {}

-- UI state
display.monitor = nil
display.monitorName = nil
display.scrollOffset = 0
display.activeTab = "species"  -- species, apiaries, discovery, log, config
display.config = nil  -- reference to live config (set by init)

-- Layer toggle states (synced from beeos.lua)
display.layerStates = {
  tracker = true,
  apiary = false,
  sampler = false,
  discovery = false,
}

-- Config tab state
display.pickerMode = nil    -- nil or { role = "chests.droneBuffer", label = "Drone Buffer" }
display.pickerList = {}     -- list of peripheral names for picker
display.pickerScroll = 0
display.updateStatus = nil  -- nil or "updating" or "done: 16 OK, 0 failed"

-- Config roles displayed on Config tab
local CONFIG_ROLES = {
  { key = "chests.droneBuffer",      label = "Drone Buffer" },
  { key = "chests.sampleStorage",    label = "Sample Storage" },
  { key = "chests.export",           label = "Export (AE2)" },
  { key = "chests.templateOutput",   label = "Template Output" },
  { key = "chests.supplyInput",      label = "Supply Input" },
  { key = "chests.princessStorage",  label = "Princess Store" },
  { key = "turtle.name",            label = "Turtle" },
  { key = "machines.analyzer",      label = "Analyzer" },
}

--- Initialize the display.
-- @param config BeeOS config
function display.init(config)
  display.config = config

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

--- Get a config value by dot path from live config.
local function getConfigValue(path)
  if not display.config then return nil end
  local section, key = path:match("^(%w+)%.(%w+)$")
  if section and key and display.config[section] then
    return display.config[section][key]
  end
  return nil
end

--- Save a config override from the display.
local function saveConfigValue(path, value)
  if not display.config then return end
  local section, key = path:match("^(%w+)%.(%w+)$")
  if not section or not key then return end
  if not display.config[section] then return end

  display.config[section][key] = value

  local overrides = state.load("config_overrides", {})
  if not overrides[section] then
    overrides[section] = {}
  end
  overrides[section][key] = value
  state.save("config_overrides", overrides)
end

--- Draw the tab bar at the top.
local function drawTabs(mon, w)
  local tabs = {
    { id = "species", label = "Species" },
    { id = "apiaries", label = "Apiaries" },
    { id = "discovery", label = "Discov" },
    { id = "log", label = "Log" },
    { id = "config", label = "Config" },
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

--- Scan network peripherals for the picker, filtered by role type.
local function scanPeripherals(roleKey)
  local results = {}
  for _, name in ipairs(peripheral.getNames()) do
    local pType = peripheral.getType(name)
    if roleKey:find("^chests%.") then
      -- For chest roles, show anything with an inventory (has .size())
      local p = peripheral.wrap(name)
      if p and p.size then
        results[#results + 1] = name
      end
    elseif roleKey == "turtle.name" then
      if pType and pType:find("turtle") then
        results[#results + 1] = name
      end
    elseif roleKey == "machines.analyzer" then
      -- Forestry analyzer or anything with bee analysis methods
      if name:find("analyzer") or name:find("forestry") then
        results[#results + 1] = name
      end
    else
      results[#results + 1] = name
    end
  end
  table.sort(results)
  return results
end

--- Draw the config tab (normal mode — shows role assignments).
local function drawConfig(mon, w, h, startY)
  local y = startY

  drawText(mon, 1, y, "Configuration", colors.yellow, colors.black)
  y = y + 1
  drawLine(mon, y, w, "-")
  y = y + 1

  -- Column positions
  local nameCol = 1
  local valueCol = 19
  local scanCol = w - 5

  for _, role in ipairs(CONFIG_ROLES) do
    if y > h - 2 then break end

    local val = getConfigValue(role.key)
    local displayVal = val or "<not set>"

    -- Truncate long peripheral names
    local maxValLen = scanCol - valueCol - 1
    if #displayVal > maxValLen then
      displayVal = displayVal:sub(1, maxValLen - 1) .. "~"
    end

    drawText(mon, nameCol, y, role.label, colors.white, colors.black)
    drawText(mon, valueCol, y, displayVal, val and colors.lime or colors.lightGray)

    -- [Scan] button
    drawText(mon, scanCol, y, "[Scan]", colors.cyan, colors.black)
    y = y + 1
  end

  -- Update button
  y = y + 1
  if y <= h then
    if display.updateStatus then
      drawText(mon, 1, y, display.updateStatus, colors.yellow, colors.black)
    else
      drawText(mon, 1, y, " [Update BeeOS] ", colors.white, colors.purple)
    end
  end
end

--- Draw the peripheral picker overlay.
local function drawPicker(mon, w, h, startY)
  local y = startY

  drawText(mon, 1, y, "Select: " .. display.pickerMode.label, colors.yellow, colors.black)
  drawText(mon, w - 5, y, "[Back]", colors.red, colors.black)
  y = y + 1
  drawLine(mon, y, w, "-")
  y = y + 1

  -- "<none>" option to clear
  drawText(mon, 2, y, "<clear>", colors.orange, colors.black)
  y = y + 1

  local maxRows = h - y
  for i = 1 + display.pickerScroll, math.min(#display.pickerList, maxRows + display.pickerScroll) do
    if y > h then break end
    drawText(mon, 2, y, display.pickerList[i], colors.white, colors.black)
    y = y + 1
  end

  if #display.pickerList == 0 then
    drawText(mon, 2, y, "No peripherals found", colors.lightGray, colors.black)
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

  -- Separator
  drawLine(mon, 3, w, "-")

  -- Content area starts at line 4
  local startY = 4

  if display.pickerMode then
    drawPicker(mon, w, h, startY)
  elseif display.activeTab == "species" then
    drawSpecies(mon, w, h, startY)
  elseif display.activeTab == "apiaries" then
    drawApiaries(mon, w, h, startY)
  elseif display.activeTab == "discovery" then
    drawDiscovery(mon, w, h, startY)
  elseif display.activeTab == "log" then
    drawLog(mon, w, h, startY)
  elseif display.activeTab == "config" then
    drawConfig(mon, w, h, startY)
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
  local w = select(1, display.monitor.getSize())

  -- Picker mode touch handling
  if display.pickerMode then
    -- [Back] button (top-right area)
    if y == 4 and x >= w - 5 then
      display.pickerMode = nil
      display.pickerList = {}
      display.pickerScroll = 0
      return { action = "tab", tab = "config" }
    end

    -- <clear> option (line 6 = startY + 2)
    if y == 6 then
      saveConfigValue(display.pickerMode.key, nil)
      tracker.addLog("Config cleared: " .. display.pickerMode.label)
      display.pickerMode = nil
      display.pickerList = {}
      display.pickerScroll = 0
      return { action = "config_set" }
    end

    -- Peripheral selection (lines 7+)
    local idx = (y - 7) + 1 + display.pickerScroll
    if idx >= 1 and idx <= #display.pickerList then
      local selected = display.pickerList[idx]
      saveConfigValue(display.pickerMode.key, selected)
      tracker.addLog("Config set: " .. display.pickerMode.label .. " = " .. selected)
      display.pickerMode = nil
      display.pickerList = {}
      display.pickerScroll = 0
      return { action = "config_set" }
    end

    return nil
  end

  -- Tab selection (line 1)
  if y == 1 then
    local tabs = { "species", "apiaries", "discovery", "log", "config" }
    local tabWidths = { 9, 10, 8, 5, 8 }
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

  -- Layer toggles (line 2)
  if y == 2 then
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

  -- Config tab specific touches
  if display.activeTab == "config" then
    local scanCol = w - 5

    -- [Scan] buttons: roles start at line 6 (startY + header + separator)
    for i, role in ipairs(CONFIG_ROLES) do
      if y == 4 + 2 + (i - 1) and x >= scanCol then
        display.pickerMode = { key = role.key, label = role.label }
        display.pickerList = scanPeripherals(role.key)
        display.pickerScroll = 0
        return { action = "picker_open" }
      end
    end

    -- [Update BeeOS] button
    local updateY = 4 + 2 + #CONFIG_ROLES + 1
    if y == updateY and not display.updateStatus then
      return { action = "update" }
    end
  end

  return nil
end

return display
