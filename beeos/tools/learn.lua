-- BeeOS Template Hash Learner
-- Interactive tool for registering genetic template nbtHash->species mappings.
--
-- Usage:
--   learn              Interactive: pick peripheral, learn all unknown templates
--   learn <peri> <slot> Learn a single slot

local args = { ... }

-- Inline state helpers (tools can't require("lib.state") from tools/ dir)
local STATE_DIR = "data"
local function stateLoad(key, default)
  local path = STATE_DIR .. "/" .. key .. ".dat"
  if not fs.exists(path) then return default end
  local f = fs.open(path, "r")
  if not f then return default end
  local content = f.readAll()
  f.close()
  local ok, data = pcall(textutils.unserialise, content)
  if ok and data ~= nil then return data end
  return default
end
local function stateSave(key, data)
  local f = fs.open(STATE_DIR .. "/" .. key .. ".dat", "w")
  if not f then return end
  f.write(textutils.serialise(data))
  f.close()
end

--- Title-case a species name: "forest" -> "Forest", "rock salt" -> "Rock Salt"
local function titleCase(s)
  if not s or s == "" then return s end
  return s:gsub("(%a)([%w]*)", function(first, rest)
    return first:upper() .. rest:lower()
  end)
end

--- Build sorted species list from persisted state for autocomplete.
local function buildSpeciesList()
  local seen = {}
  local list = {}
  local function add(sp)
    if not seen[sp] then seen[sp] = true; list[#list + 1] = sp end
  end
  for sp in pairs(stateLoad("discovered", {})) do add(sp) end
  for sp in pairs(stateLoad("catalog", {})) do add(sp) end
  -- Also pull species from already-learned template hashes
  for _, sp in pairs(stateLoad("template_hashes", {})) do add(sp) end
  table.sort(list)
  return list
end

--- Find peripherals with inventory support (have a "size" method).
local function findInventories()
  local result = {}
  for _, name in ipairs(peripheral.getNames()) do
    local methods = peripheral.getMethods(name)
    if methods then
      for _, m in ipairs(methods) do
        if m == "size" then
          result[#result + 1] = name
          break
        end
      end
    end
  end
  table.sort(result)
  return result
end

--- Interactive peripheral selector. Returns peripheral name or nil.
local function selectPeripheral()
  local inventories = findInventories()
  if #inventories == 0 then
    printError("No inventory peripherals found.")
    return nil
  end

  term.setTextColor(colors.yellow)
  print("Select inventory:")
  term.setTextColor(colors.white)

  local lineY = {}
  for i, name in ipairs(inventories) do
    lineY[i] = select(2, term.getCursorPos())
    print(" " .. i .. ". " .. name)
  end

  term.setTextColor(colors.lightGray)
  write("> ")
  term.setTextColor(colors.white)

  local input = ""
  term.setCursorBlink(true)
  while true do
    local ev, p1, _, p3 = os.pullEvent()

    if ev == "char" then
      input = input .. p1
      write(p1)

    elseif ev == "key" then
      if p1 == keys.enter and input ~= "" then
        local n = tonumber(input)
        if n and n >= 1 and n <= #inventories then
          print()
          term.setCursorBlink(false)
          return inventories[n]
        end
      elseif p1 == keys.backspace and #input > 0 then
        input = input:sub(1, -2)
        local cx, cy = term.getCursorPos()
        term.setCursorPos(cx - 1, cy)
        write(" ")
        term.setCursorPos(cx - 1, cy)
      end

    elseif ev == "mouse_click" then
      for i = 1, #inventories do
        if p3 == lineY[i] then
          print(i)
          term.setCursorBlink(false)
          return inventories[i]
        end
      end
    end
  end
end

--- Read input with species autocomplete suggestions.
-- @param prompt Prompt text
-- @param speciesList Sorted list of known species
-- @return string input
local function readSpecies(prompt, speciesList)
  term.setTextColor(colors.yellow)
  write(prompt)
  term.setTextColor(colors.white)

  local inputX, inputY = term.getCursorPos()
  local w, h = term.getSize()
  local input = ""
  local maxShow = math.min(5, h - inputY)

  local function getMatches()
    if input == "" then return {} end
    local matches = {}
    local lower = input:lower()
    for _, sp in ipairs(speciesList) do
      if sp:lower():find(lower, 1, true) == 1 then
        matches[#matches + 1] = sp
        if #matches >= maxShow then break end
      end
    end
    return matches
  end

  local function clearSuggestions()
    for i = 1, maxShow do
      local y = inputY + i
      if y > h then break end
      term.setCursorPos(1, y)
      term.clearLine()
    end
  end

  local function render()
    -- Redraw input line
    term.setCursorPos(inputX, inputY)
    local pad = w - inputX - #input + 1
    write(input .. string.rep(" ", math.max(0, pad)))

    -- Draw suggestions
    local matches = getMatches()
    for i = 1, maxShow do
      local y = inputY + i
      if y > h then break end
      term.setCursorPos(1, y)
      term.clearLine()
      if i <= #matches then
        term.setTextColor(colors.cyan)
        write(" " .. i .. ". " .. matches[i])
      end
    end

    -- Restore cursor
    term.setCursorPos(inputX + #input, inputY)
    term.setTextColor(colors.white)
    return matches
  end

  term.setCursorBlink(true)
  local matches = render()

  while true do
    local ev, p1, _, p3 = os.pullEvent()

    if ev == "char" then
      input = input .. p1
      matches = render()

    elseif ev == "key" then
      if p1 == keys.enter then
        clearSuggestions()
        term.setCursorPos(1, inputY + 1)
        term.setCursorBlink(false)
        return input
      elseif p1 == keys.backspace and #input > 0 then
        input = input:sub(1, -2)
        matches = render()
      elseif p1 == keys.tab and #matches > 0 then
        input = matches[1]
        matches = render()
      end

    elseif ev == "mouse_click" then
      local idx = p3 - inputY
      if idx >= 1 and idx <= #matches then
        input = matches[idx]
        clearSuggestions()
        term.setCursorPos(inputX, inputY)
        local pad = w - inputX - #input + 1
        write(input .. string.rep(" ", math.max(0, pad)))
        term.setCursorPos(1, inputY + 1)
        term.setCursorBlink(false)
        return input
      end
    end
  end
end

--- Learn a single slot. Returns true if learned/known, false if skipped.
local function learnSlot(peri, s, speciesList)
  local meta = peri.getItemMeta and peri.getItemMeta(s)
  if not meta then
    print("Slot " .. s .. " is empty.")
    return false
  end

  if not (meta.name or ""):find("gene_template") then
    print("Slot " .. s .. ": not a template (" .. (meta.displayName or meta.name or "?") .. ")")
    return false
  end

  local nbtHash = meta.nbtHash
  if not nbtHash then
    printError("Slot " .. s .. ": no nbtHash")
    return false
  end

  local map = stateLoad("template_hashes", {})
  if map[nbtHash] then
    term.setTextColor(colors.lime)
    print("Slot " .. s .. ": already known as " .. map[nbtHash])
    term.setTextColor(colors.white)
    return true
  end

  local species = readSpecies("Slot " .. s .. " species: ", speciesList)
  if not species or species == "" then
    print("Skipped.")
    return false
  end

  species = titleCase(species)
  map[nbtHash] = species
  stateSave("template_hashes", map)

  term.setTextColor(colors.lime)
  print("Learned: " .. species .. " (" .. nbtHash:sub(1, 12) .. "...)")
  term.setTextColor(colors.white)
  return true
end

--- Walk all slots in a peripheral, prompting for unknown templates.
local function walkAll(peri, speciesList)
  local size = peri.size and peri.size() or 0
  local map = stateLoad("template_hashes", {})

  local unknown = {}
  local known = 0
  for s = 1, size do
    local meta = peri.getItemMeta and peri.getItemMeta(s)
    if meta and (meta.name or ""):find("gene_template") then
      local hash = meta.nbtHash
      if hash then
        if map[hash] then
          known = known + 1
        else
          unknown[#unknown + 1] = s
        end
      end
    end
  end

  if #unknown == 0 then
    term.setTextColor(colors.lime)
    print("All templates known (" .. known .. " total).")
    term.setTextColor(colors.white)
    return
  end

  print("Found " .. #unknown .. " unknown, " .. known .. " known.")
  if #speciesList == 0 then
    printError("No known species for autocomplete.")
    printError("Run BeeOS (or a scan) first to populate the catalog.")
    return
  end
  term.setTextColor(colors.lightGray)
  print("Tab/click to autocomplete. Input is title-cased automatically.")
  term.setTextColor(colors.white)
  print()

  local learned = 0
  for _, s in ipairs(unknown) do
    if learnSlot(peri, s, speciesList) then
      learned = learned + 1
    end
  end

  print()
  term.setTextColor(colors.yellow)
  print("Done: " .. learned .. " learned, " .. (#unknown - learned) .. " skipped.")
  term.setTextColor(colors.white)
end

-- Main
if #args >= 1 then
  -- Single-slot mode
  local periName = args[1]
  local slot = tonumber(args[2]) or 1
  local p = peripheral.wrap(periName)
  if not p then
    printError("Peripheral not found: " .. periName)
    return
  end
  local speciesList = buildSpeciesList()
  if #speciesList == 0 then
    printError("No known species for autocomplete. Run BeeOS first.")
    return
  end
  learnSlot(p, slot, speciesList)
else
  -- Interactive mode
  term.setTextColor(colors.yellow)
  print("=== Template Learner ===")
  term.setTextColor(colors.white)
  print()

  local periName = selectPeripheral()
  if not periName then return end

  local p = peripheral.wrap(periName)
  if not p then
    printError("Failed to wrap: " .. periName)
    return
  end

  print()
  print("Scanning " .. periName .. "...")
  walkAll(p, buildSpeciesList())
end
