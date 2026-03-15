-- BeeOS Display Manager
-- Renders status information to an Advanced Monitor with touch controls.

local tracker = require("lib.tracker")
local apiary = require("lib.apiary")
local discovery = require("lib.discovery")
local mutations = require("lib.mutations")
local sampler = require("lib.sampler")
local imprinter = require("lib.imprinter")
local analyzer = require("lib.analyzer")
local inventory = require("lib.inventory")
local state = require("lib.state")

local display = {}

-- UI state
display.monitor = nil
display.monitorName = nil
display.scrollOffset = 0
display.activeTab = "species"  -- species, machines, discovery, log, config
display.config = nil  -- reference to live config (set by init)
display.machines = nil  -- reference to network.scan() result (set by beeos.lua)

-- Layer toggle states (synced from beeos.lua)
display.layerStates = {
  tracker = true,
  apiary = false,
  sampler = false,
  discovery = false,
  surplus = false,
  traitExport = false,
}

-- Config tab state
display.pickerMode = nil    -- nil or { role = "chests.droneBuffer", label = "Drone Buffer" }
display.pickerList = {}     -- list of peripheral names for picker
display.pickerScroll = 0
display.updateStatus = nil  -- nil or "updating" or "done: 16 OK, 0 failed"

-- Config roles displayed on Config tab
local CONFIG_ROLES = {
  { key = "chests.droneBuffer",       label = "Drone Buffer",     multi = true },
  { key = "chests.sampleStorage",     label = "Sample Storage",   multi = true },
  { key = "chests.export",            label = "Export (AE2)",     multi = true },
  { key = "chests.templateOutput",    label = "Template Output",  multi = true },
  { key = "chests.supplyInput",       label = "Supply Input",     multi = true },
  { key = "chests.princessStorage",   label = "Princess Store",   multi = true },
  { key = "chests.traitTemplates",    label = "Trait Templates",  multi = true },
  { key = "chests.discoveryStaging",  label = "Disco Staging",    multi = true },
  { key = "turtle.name",             label = "Craft Turtle",     multi = false },
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
    { id = "machines", label = "Machines" },
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
    { id = "surplus", label = "Surpl" },
    { id = "traitExport", label = "TrExp" },
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

--- Check if a species appears in any value of an activeSpecies table.
local function isActiveIn(activeTable, species)
  if not activeTable then return false end
  for _, sp in pairs(activeTable) do
    if sp == species then return true end
  end
  return false
end

--- Check if a species is being bred in any running apiary.
local function isBreeding(species)
  for _, status in pairs(apiary.status) do
    if status.state == "running" and status.species == species then
      return true
    end
  end
  return false
end

--- Get the activity indicator letter and color for a species.
-- Priority: D > I > A > S > B
local function getActivityIndicator(species)
  if discovery.currentTarget == species then
    return "D", colors.cyan
  end
  if isActiveIn(imprinter.activeSpecies, species) then
    return "I", colors.yellow
  end
  if isActiveIn(analyzer.activeSpecies, species) then
    return "A", colors.orange
  end
  if isActiveIn(sampler.activeSpecies, species) then
    return "S", colors.purple
  end
  if isActiveIn(sampler.activeTransposer, species) then
    return "T", colors.magenta
  end
  if isBreeding(species) then
    return "B", colors.lime
  end
  return nil, nil
end

--- Draw the species catalog tab.
local function drawSpecies(mon, w, h, startY)
  local species = tracker.sortedSpecies()

  -- Re-sort: discovery target first, then machine-active, then normal
  table.sort(species, function(a, b)
    local aInd = getActivityIndicator(a.name)
    local bInd = getActivityIndicator(b.name)
    local aDisco = aInd == "D"
    local bDisco = bInd == "D"
    if aDisco ~= bDisco then return aDisco end
    local aActive = aInd ~= nil
    local bActive = bInd ~= nil
    if aActive ~= bActive then return aActive end
    -- Within same group, keep original color+alpha order
    local colorOrder = { [colors.red] = 1, [colors.orange] = 2, [colors.lime] = 3, [colors.gray] = 4 }
    local ao = colorOrder[a.color] or 5
    local bo = colorOrder[b.color] or 5
    if ao ~= bo then return ao < bo end
    return a.name < b.name
  end)

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

  -- Species rows (reserve 4 lines for footer separator, stats, color key, activity key)
  local maxRows = math.max(1, h - y - 4)
  display.speciesPageSize = maxRows
  display.speciesTotal = #species

  -- Clamp scroll offset
  local maxOffset = math.max(0, #species - maxRows)
  if display.scrollOffset > maxOffset then
    display.scrollOffset = maxOffset
  end

  -- Page indicator in header area
  if #species > maxRows then
    local page = math.floor(display.scrollOffset / maxRows) + 1
    local totalPages = math.ceil(#species / maxRows)
    local pageStr = "[<] " .. page .. "/" .. totalPages .. " [>]"
    drawText(mon, w - #pageStr, startY, pageStr, colors.cyan, colors.black)
  end

  for i = 1 + display.scrollOffset, math.min(#species, maxRows + display.scrollOffset) do
    local sp = species[i]
    if sp and y <= h then
      -- Status indicator
      drawText(mon, 1, y, "*", sp.color, colors.black)
      -- Activity indicator
      local actLetter, actColor = getActivityIndicator(sp.name)
      if actLetter then
        drawText(mon, 2, y, actLetter, actColor, colors.black)
      end
      -- Name (truncated)
      local name = sp.name
      if #name > 15 then name = name:sub(1, 14) .. "~" end
      drawText(mon, 4, y, name, colors.white)
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
    y = y + 1
  end

  -- Color key (only if enough vertical space)
  if y <= h then
    local x = 1
    drawText(mon, x, y, "*", colors.lime, colors.black)
    x = x + 1
    drawText(mon, x, y, "Stocked ", colors.lightGray, colors.black)
    x = x + 8
    drawText(mon, x, y, "*", colors.orange)
    x = x + 1
    drawText(mon, x, y, "Low ", colors.lightGray)
    x = x + 4
    drawText(mon, x, y, "*", colors.red)
    x = x + 1
    drawText(mon, x, y, "Needs attn ", colors.lightGray)
    x = x + 11
    drawText(mon, x, y, "*", colors.gray)
    x = x + 1
    drawText(mon, x, y, "Undiscovered", colors.lightGray)
    y = y + 1
  end

  -- Activity key
  if y <= h then
    local x2 = 1
    drawText(mon, x2, y, "D", colors.cyan, colors.black)
    drawText(mon, x2 + 1, y, "isco ", colors.lightGray)
    x2 = x2 + 6
    drawText(mon, x2, y, "I", colors.yellow)
    drawText(mon, x2 + 1, y, "mpr ", colors.lightGray)
    x2 = x2 + 5
    drawText(mon, x2, y, "A", colors.orange)
    drawText(mon, x2 + 1, y, "nalyz ", colors.lightGray)
    x2 = x2 + 7
    drawText(mon, x2, y, "S", colors.purple)
    drawText(mon, x2 + 1, y, "ampl ", colors.lightGray)
    x2 = x2 + 6
    drawText(mon, x2, y, "T", colors.magenta)
    drawText(mon, x2 + 1, y, "rans ", colors.lightGray)
    x2 = x2 + 6
    drawText(mon, x2, y, "B", colors.lime)
    drawText(mon, x2 + 1, y, "reed", colors.lightGray)
  end
end

--- Get machine status (species, state, color) by category.
local function getMachineStatus(category, name)
  if category == "apiary" then
    local s = apiary.status[name]
    if s then
      local clr = s.state == "running" and colors.lime
        or s.state == "restarting" and colors.yellow or colors.lightGray
      return s.species or "-", s.state, clr
    end
    return "-", "idle", colors.lightGray
  elseif category == "sampler" then
    local sp = sampler.activeSpecies[name]
    return sp or "-", sp and "sampling" or "idle",
      sp and colors.lime or colors.lightGray
  elseif category == "imprinter" then
    local sp = imprinter.activeSpecies[name]
    return sp or "-", sp and "imprinting" or "idle",
      sp and colors.lime or colors.lightGray
  elseif category == "analyzer" then
    local sp = analyzer.activeSpecies[name]
    return sp or "-", sp and "analyzing" or "idle",
      sp and colors.lime or colors.lightGray
  elseif category == "transposer" then
    local sp = sampler.activeTransposer[name]
    return sp or "-", sp and "copying" or "idle",
      sp and colors.lime or colors.lightGray
  elseif category == "mutatron" then
    if discovery.state == "mutating" and discovery.currentTarget then
      return discovery.currentTarget, "mutating", colors.lime
    end
    return "-", "idle", colors.lightGray
  end
  return "-", "-", colors.lightGray
end

--- Machine categories to display.
local MACHINE_CATEGORIES = {
  { key = "apiary",       label = "Apiaries" },
  { key = "sampler",      label = "Samplers" },
  { key = "imprinter",    label = "Imprinters" },
  { key = "analyzer",     label = "Analyzers" },
  { key = "mutatron",     label = "Mutatrons" },
  { key = "transposer",   label = "Transposers" },
  { key = "dnaExtractor", label = "Extractors" },
}

--- Draw the machines tab.
local function drawMachines(mon, w, h, startY)
  local y = startY
  local anyMachines = false

  drawText(mon, 1, y, "Machine", colors.yellow, colors.black)
  drawText(mon, 24, y, "Species", colors.yellow)
  drawText(mon, 37, y, "Status", colors.yellow)
  y = y + 1
  drawLine(mon, y, w, "-")
  y = y + 1

  for _, cat in ipairs(MACHINE_CATEGORIES) do
    local machineTable = display.machines and display.machines[cat.key] or {}
    local count = 0
    for _ in pairs(machineTable) do count = count + 1 end

    if count > 0 then
      if y > h then break end
      anyMachines = true

      -- Section header
      drawText(mon, 1, y, cat.label .. " (" .. count .. ")",
        colors.yellow, colors.black)
      y = y + 1

      -- Sort machine names for stable display
      local names = {}
      for name in pairs(machineTable) do
        names[#names + 1] = name
      end
      table.sort(names)

      local mutatronShown = false
      for _, name in ipairs(names) do
        if y > h then break end

        local sp, st, stColor
        if cat.key == "mutatron" and not mutatronShown then
          sp, st, stColor = getMachineStatus(cat.key, name)
          mutatronShown = true
        elseif cat.key == "mutatron" then
          sp, st, stColor = "-", "idle", colors.lightGray
        else
          sp, st, stColor = getMachineStatus(cat.key, name)
        end

        -- Machine name (truncated)
        local displayName = name
        if #displayName > 20 then
          displayName = displayName:sub(1, 19) .. "~"
        end
        drawText(mon, 3, y, displayName, colors.white, colors.black)

        -- Species (truncated)
        local displaySp = sp
        if #displaySp > 12 then
          displaySp = displaySp:sub(1, 11) .. "~"
        end
        drawText(mon, 24, y, displaySp, colors.cyan)

        -- State
        drawText(mon, 37, y, st, stColor)
        y = y + 1
      end
    end
  end

  if not anyMachines then
    drawText(mon, 1, y, "No machines detected", colors.lightGray, colors.black)
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

  -- State with sub-step
  drawText(mon, 1, y, "State:    ", colors.lightGray, colors.black)
  local stateColors = {
    idle = colors.lightGray,
    preparing = colors.yellow,
    imprinting = colors.orange,
    mutating = colors.lime,
  }
  local stateColor = stateColors[progress.state] or colors.lightGray
  local stateLabel = progress.state
  if progress.state == "imprinting" and progress.imprintStep then
    stateLabel = stateLabel .. " (" .. progress.imprintStep .. ")"
  end
  drawText(mon, 11, y, stateLabel, stateColor)
  y = y + 1

  -- Idle reason
  if progress.state == "idle" and progress.idleReason then
    drawText(mon, 1, y, "Reason:   ", colors.lightGray, colors.black)
    drawText(mon, 11, y, progress.idleReason, colors.orange)
    y = y + 1
  end

  -- Discovery needs
  local needs = discovery.needs or {}
  local needsList = {}
  for sp, need in pairs(needs) do
    needsList[#needsList + 1] = sp .. "=" .. need
  end
  if #needsList > 0 and y + 1 <= h then
    drawText(mon, 1, y, "Needs:    ", colors.lightGray, colors.black)
    drawText(mon, 11, y, table.concat(needsList, ", "), colors.orange)
    y = y + 1
  end

  if progress.currentTarget then
    y = y + 1
    drawText(mon, 1, y, "Target:  ", colors.lightGray, colors.black)
    drawText(mon, 10, y, progress.currentTarget, colors.cyan)
    y = y + 1

    if progress.currentMutation then
      drawText(mon, 1, y, "Parents: ", colors.lightGray, colors.black)
      drawText(mon, 10, y, progress.currentMutation.parent1 .. " + " ..
        progress.currentMutation.parent2, colors.white)
      y = y + 1

      drawText(mon, 1, y, "Chance:  ", colors.lightGray, colors.black)
      drawText(mon, 10, y, string.format("%.0f%%", (progress.currentMutation.chance or 0) * 100),
        colors.orange)
      y = y + 1
    end

    drawText(mon, 1, y, "Attempt: ", colors.lightGray, colors.black)
    drawText(mon, 10, y, tostring(progress.attempts), colors.white)
    y = y + 1
  end

  -- Candidate queue
  local candidates = progress.candidates or {}
  if #candidates > 0 and y + 2 <= h then
    y = y + 1
    drawText(mon, 1, y, "Next Up:", colors.yellow, colors.black)
    y = y + 1
    for _, cand in ipairs(candidates) do
      if y > h - 3 then break end  -- Reserve space for progress bar
      local prefix = " "
      local nameColor = colors.white
      if cand.species == progress.currentTarget then
        prefix = ">"
        nameColor = colors.cyan
      end
      local chance = string.format("%3.0f%%", (cand.mutation.chance or 0) * 100)
      local parents = cand.mutation.parent1 .. "+" .. cand.mutation.parent2
      -- Truncate parents if too long
      local maxParents = w - 7 - #cand.species
      if #parents > maxParents and maxParents > 3 then
        parents = parents:sub(1, maxParents - 1) .. "~"
      end
      drawText(mon, 1, y, prefix, nameColor, colors.black)
      drawText(mon, 2, y, chance, colors.orange)
      drawText(mon, 7, y, cand.species, nameColor)
      drawText(mon, 7 + #cand.species + 1, y, parents, colors.lightGray)
      y = y + 1
    end
  end

  -- Blocked parents requiring user action
  local blocked = discovery.blockedParents or {}
  if next(blocked) and y + 2 <= h then
    y = y + 1
    drawText(mon, 1, y, "NEED:", colors.red, colors.black)
    y = y + 1
    for species in pairs(blocked) do
      if y > h - 3 then break end
      drawText(mon, 2, y, species .. " princess+drone", colors.red, colors.black)
      y = y + 1
    end
  end

  -- Progress bar
  if progress.total > 0 then
    y = y + 1
    if y + 1 <= h then
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
      drawText(mon, 1, y, string.format("%.1f%% complete", pct * 100),
        colors.lightGray, colors.black)
    end
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
      local msg = entry.message or ""
      local msgCol = #timeStr + 1
      local maxMsgLen = w - msgCol + 1

      drawText(mon, 1, y, timeStr, colors.lightGray, colors.black)
      -- Wrap long messages across multiple lines
      while #msg > 0 and y <= h do
        local line = msg:sub(1, maxMsgLen)
        msg = msg:sub(maxMsgLen + 1)
        drawText(mon, msgCol, y, line, colors.white, colors.black)
        y = y + 1
      end
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
      if name:find("analyzer") or name:find("forestry") then
        results[#results + 1] = name
      end
    elseif roleKey == "machines.imprinters" then
      if name:find("imprinter") or name:find("gendustry") then
        results[#results + 1] = name
      end
    elseif roleKey == "machines.mutatrons" then
      if name:find("mutatron") or name:find("gendustry") then
        results[#results + 1] = name
      end
    elseif roleKey == "machines.samplers" then
      if name:find("sampler") or name:find("gendustry") then
        results[#results + 1] = name
      end
    elseif roleKey == "machines.transposers" then
      if name:find("transposer") or name:find("gendustry") then
        results[#results + 1] = name
      end
    elseif roleKey == "machines.dnaExtractors" then
      if name:find("extractor") or name:find("gendustry") then
        results[#results + 1] = name
      end
    elseif roleKey == "mutations.preset" or roleKey == "display.monitorSide" then
      -- These are text entries, not peripheral pickers — show all peripherals
      results[#results + 1] = name
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
    local displayVal

    if role.multi then
      local names = inventory.normalize(val)
      if #names == 0 then
        displayVal = "<not set>"
      elseif #names == 1 then
        displayVal = names[1]
      else
        displayVal = names[1] .. " [" .. #names .. "]"
      end
    else
      displayVal = val or "<not set>"
    end

    -- Truncate long peripheral names
    local maxValLen = scanCol - valueCol - 1
    if #displayVal > maxValLen then
      displayVal = displayVal:sub(1, maxValLen - 1) .. "~"
    end

    local hasVal = role.multi and #inventory.normalize(val) > 0 or (not role.multi and val)
    drawText(mon, nameCol, y, role.label, colors.white, colors.black)
    drawText(mon, valueCol, y, displayVal, hasVal and colors.lime or colors.lightGray)

    -- [Scan] button
    drawText(mon, scanCol, y, "[Scan]", colors.cyan, colors.black)
    y = y + 1
  end

  -- Action buttons
  y = y + 1
  if y <= h then
    drawText(mon, 1, y, " [Rescan Network] ", colors.white, colors.blue)
  end
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
  local isMulti = display.pickerMode.multi

  drawText(mon, 1, y, "Select: " .. display.pickerMode.label, colors.yellow, colors.black)
  drawText(mon, w - 5, y, "[Back]", colors.red, colors.black)
  y = y + 1
  drawLine(mon, y, w, "-")
  y = y + 1

  -- "<clear>" option to reset
  drawText(mon, 2, y, "[x] <clear all>", colors.orange, colors.black)
  y = y + 1

  -- Get current assigned names for multi mode
  local assigned = {}
  if isMulti then
    local val = getConfigValue(display.pickerMode.key)
    for _, n in ipairs(inventory.normalize(val)) do
      assigned[n] = true
    end
  end

  local maxRows = h - y
  for i = 1 + display.pickerScroll, math.min(#display.pickerList, maxRows + display.pickerScroll) do
    if y > h then break end
    local name = display.pickerList[i]
    if isMulti then
      local prefix = assigned[name] and "[-] " or "[+] "
      local clr = assigned[name] and colors.red or colors.lime
      drawText(mon, 2, y, prefix, clr, colors.black)
      drawText(mon, 6, y, name, colors.white, colors.black)
    else
      drawText(mon, 2, y, name, colors.white, colors.black)
    end
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
  local titleInfo = string.format(" %d species ", stats.discovered)
  drawText(mon, 9, 1, titleInfo, colors.white, colors.black)
  if mutations.source then
    drawText(mon, 9 + #titleInfo, 1, " " .. mutations.source .. " ", colors.lightGray, colors.black)
  end

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
  elseif display.activeTab == "machines" then
    drawMachines(mon, w, h, startY)
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
    local isMulti = display.pickerMode.multi

    -- [Back] button (top-right area)
    if y == 4 and x >= w - 5 then
      display.pickerMode = nil
      display.pickerList = {}
      display.pickerScroll = 0
      return { action = "tab", tab = "config" }
    end

    -- <clear all> option (line 6 = startY + 2)
    if y == 6 then
      saveConfigValue(display.pickerMode.key, nil)
      tracker.addLog("Config cleared: " .. display.pickerMode.label)
      if not isMulti then
        display.pickerMode = nil
        display.pickerList = {}
        display.pickerScroll = 0
      end
      return { action = "config_set" }
    end

    -- Peripheral selection (lines 7+)
    local idx = (y - 7) + 1 + display.pickerScroll
    if idx >= 1 and idx <= #display.pickerList then
      local selected = display.pickerList[idx]

      if isMulti then
        -- Toggle: add or remove from the array
        local val = getConfigValue(display.pickerMode.key)
        local current = inventory.normalize(val)
        local found = false
        local newList = {}
        for _, n in ipairs(current) do
          if n == selected then
            found = true
          else
            newList[#newList + 1] = n
          end
        end
        if not found then
          newList[#newList + 1] = selected
        end
        -- Save as array if >1, string if 1, nil if 0
        local saveVal
        if #newList == 0 then
          saveVal = nil
        elseif #newList == 1 then
          saveVal = newList[1]
        else
          saveVal = newList
        end
        saveConfigValue(display.pickerMode.key, saveVal)
        local action_word = found and "removed" or "added"
        tracker.addLog("Config " .. action_word .. ": " ..
          display.pickerMode.label .. " " .. selected)
        -- Stay in picker for multi mode
      else
        saveConfigValue(display.pickerMode.key, selected)
        tracker.addLog("Config set: " .. display.pickerMode.label .. " = " .. selected)
        display.pickerMode = nil
        display.pickerList = {}
        display.pickerScroll = 0
      end
      return { action = "config_set" }
    end

    return nil
  end

  -- Tab selection (line 1)
  if y == 1 then
    local tabs = { "species", "machines", "discovery", "log", "config" }
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
      { 53, 63, "surplus" },
      { 64, 75, "traitExport" },
    }
    for _, range in ipairs(ranges) do
      if x >= range[1] and x <= range[2] then
        return { action = "toggle", layer = range[3] }
      end
    end
  end

  -- Species tab pagination (line 4 = startY, right side has [<] page [>])
  if display.activeTab == "species" and y == 4 then
    local pageSize = display.speciesPageSize or 1
    local total = display.speciesTotal or 0
    local maxOffset = math.max(0, total - pageSize)
    -- [<] button area (right side of header)
    if x >= w - 15 and x <= w - 12 then
      display.scrollOffset = math.max(0, display.scrollOffset - pageSize)
      return { action = "scroll" }
    end
    -- [>] button area
    if x >= w - 2 then
      display.scrollOffset = math.min(maxOffset, display.scrollOffset + pageSize)
      return { action = "scroll" }
    end
  end

  -- Config tab specific touches
  if display.activeTab == "config" then
    local scanCol = w - 5

    -- [Scan] buttons: roles start at line 6 (startY + header + separator)
    for i, role in ipairs(CONFIG_ROLES) do
      if y == 4 + 2 + (i - 1) and x >= scanCol then
        display.pickerMode = { key = role.key, label = role.label, multi = role.multi }
        display.pickerList = scanPeripherals(role.key)
        display.pickerScroll = 0
        return { action = "picker_open" }
      end
    end

    -- [Rescan Network] button
    local rescanY = 4 + 2 + #CONFIG_ROLES + 1
    if y == rescanY then
      return { action = "rescan" }
    end

    -- [Update BeeOS] button
    local updateY = rescanY + 1
    if y == updateY and not display.updateStatus then
      return { action = "update" }
    end
  end

  return nil
end

return display
