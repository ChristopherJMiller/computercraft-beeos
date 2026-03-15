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

--- Normalize species name by stripping mod registry prefixes.
-- Mirrors bee.normalizeSpecies() (can't require lib.bee from tools/).
local function normalizeSpecies(name)
  if not name then return name end
  return name:match("%.bees%.species%.(.+)$") or name
end

--- Title-case a species name: "forest" -> "Forest", "rock salt" -> "Rock Salt"
local function titleCase(s)
  if not s or s == "" then return s end
  return s:gsub("(%a)([%w]*)", function(first, rest)
    return first:upper() .. rest:lower()
  end)
end

--- Load all species from mutations preset file.
local function loadPresetSpecies()
  local path = "data/presets/meatballcraft.lua"
  if not fs.exists(path) then return {} end
  local fn, err = loadfile(path)
  if not fn then
    printError("Preset load error: " .. (err or "unknown"))
    return {}
  end
  local ok, preset = pcall(fn)
  if not ok or not preset or not preset.mutations then return {} end
  local species = {}
  for result, parents in pairs(preset.mutations) do
    species[result] = true
    for _, entry in ipairs(parents) do
      if entry.parent1 then species[entry.parent1] = true end
      if entry.parent2 then species[entry.parent2] = true end
    end
  end
  return species
end

--- Build sorted species list for autocomplete.
-- Merges preset mutations (full modpack list) + runtime state.
local function buildSpeciesList()
  local seen = {}
  local list = {}
  local function add(sp)
    if not seen[sp] then seen[sp] = true; list[#list + 1] = sp end
  end
  -- Preset has the full species list
  for sp in pairs(loadPresetSpecies()) do add(sp) end
  -- Runtime state may have species not in preset (custom/MagicBees)
  for sp in pairs(stateLoad("discovered", {})) do add(sp) end
  for sp in pairs(stateLoad("catalog", {})) do add(sp) end
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

  -- Validate against known species
  local valid = false
  for _, sp in ipairs(speciesList) do
    if sp == species then valid = true; break end
  end
  if not valid then
    term.setTextColor(colors.red)
    print("Unknown species: " .. species)
    term.setTextColor(colors.white)
    return false
  end

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
  for idx, s in ipairs(unknown) do
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.yellow)
    print("=== Template Learner (" .. idx .. "/" .. #unknown .. ") ===")
    term.setTextColor(colors.lightGray)
    print("Tab/click to autocomplete. Enter to confirm. Empty to skip.")
    term.setTextColor(colors.white)
    print()
    if learnSlot(peri, s, speciesList) then
      learned = learned + 1
    end
  end

  term.clear()
  term.setCursorPos(1, 1)
  term.setTextColor(colors.yellow)
  print("Done: " .. learned .. " learned, " .. (#unknown - learned) .. " skipped.")
  term.setTextColor(colors.white)
end

--- Scan a chest and detect samples/templates using the same logic as tracker.
-- @param periName Peripheral name
-- @return table { samples = { [species] = count }, templates = { [species] = count },
--                 unknownTemplates = count }
local function scanChest(periName)
  local result = { samples = {}, templates = {}, unknownTemplates = 0 }
  local peri = peripheral.wrap(periName)
  if not peri or not peri.size then return result end
  local templateMap = stateLoad("template_hashes", {})
  for slot = 1, peri.size() do
    local meta = peri.getItemMeta and peri.getItemMeta(slot)
    if meta then
      local name = meta.name or ""
      local display = meta.displayName or ""
      if name:find("gene_sample") and not name:find("gene_sample_blank") then
        -- Same pattern as tracker.lua:125 + normalization
        local sp = normalizeSpecies(display:match("Species:%s*(.+)$"))
        if sp then
          result.samples[sp] = (result.samples[sp] or 0) + (meta.count or 1)
        end
      elseif name:find("gene_template") then
        -- Same logic as tracker.lua:133-134
        local sp = templateMap[meta.nbtHash]
        if sp then
          result.templates[sp] = (result.templates[sp] or 0) + (meta.count or 1)
        else
          result.unknownTemplates = result.unknownTemplates + (meta.count or 1)
        end
      end
    end
  end
  return result
end

-- Main
if args[1] == "status" then
  -- Load config + runtime overrides (chest names are stored in overrides)
  local configFn = loadfile("config.lua")
  if not configFn then
    printError("Cannot load config.lua (run from BeeOS root dir)")
    return
  end
  local cfg = configFn()
  local overrides = stateLoad("config_overrides", {})
  for section, values in pairs(overrides) do
    if type(cfg[section]) == "table" and type(values) == "table" then
      for k, v in pairs(values) do
        cfg[section][k] = v
      end
    end
  end

  -- Chest configs can be a string or a table of strings (multi-chest)
  local function addChests(chestList, value, label)
    if type(value) == "string" then
      chestList[#chestList + 1] = { name = value, label = label }
    elseif type(value) == "table" then
      for _, v in ipairs(value) do
        chestList[#chestList + 1] = { name = v, label = label }
      end
    end
  end
  local chests = {}
  addChests(chests, cfg.chests.sampleStorage, "Sample Storage")
  addChests(chests, cfg.chests.templateOutput, "Template Output")
  if #chests == 0 then
    printError("No sampleStorage or templateOutput chests configured.")
    return
  end

  -- Merge results from all chests
  local allSamples = {}
  local allTemplates = {}
  local totalUnknown = 0
  for _, chest in ipairs(chests) do
    term.setTextColor(colors.lightGray)
    print("Scanning " .. chest.label .. " (" .. chest.name .. ")...")
    local data = scanChest(chest.name)
    for sp, n in pairs(data.samples) do
      allSamples[sp] = (allSamples[sp] or 0) + n
    end
    for sp, n in pairs(data.templates) do
      allTemplates[sp] = (allTemplates[sp] or 0) + n
    end
    totalUnknown = totalUnknown + data.unknownTemplates
  end

  -- Collect all species seen
  local allSpecies = {}
  local seen = {}
  for sp in pairs(allSamples) do
    if not seen[sp] then seen[sp] = true; allSpecies[#allSpecies + 1] = sp end
  end
  for sp in pairs(allTemplates) do
    if not seen[sp] then seen[sp] = true; allSpecies[#allSpecies + 1] = sp end
  end
  table.sort(allSpecies)

  print()
  term.setTextColor(colors.yellow)
  print("Species       Samples  Templates")
  term.setTextColor(colors.white)
  print(string.rep("-", 35))

  for _, sp in ipairs(allSpecies) do
    local s = allSamples[sp] or 0
    local t = allTemplates[sp] or 0
    -- Color: green if has both, orange if missing template, white otherwise
    if s >= 1 and t >= 1 then
      term.setTextColor(colors.lime)
    elseif s >= 1 and t == 0 then
      term.setTextColor(colors.orange)
    else
      term.setTextColor(colors.white)
    end
    -- Right-align counts
    local line = sp .. string.rep(" ", math.max(1, 14 - #sp))
      .. string.format("%3d      %3d", s, t)
    print(line)
  end

  if totalUnknown > 0 then
    term.setTextColor(colors.red)
    print()
    print(totalUnknown .. " template(s) with unknown hash (run 'learn' to fix)")
  end

  -- Health check: flag species names that look like internal registry IDs
  local badNames = {}
  for _, sp in ipairs(allSpecies) do
    if sp:find("%.") then
      badNames[#badNames + 1] = sp
    end
  end
  if #badNames > 0 then
    term.setTextColor(colors.red)
    print()
    print("WARNING: " .. #badNames .. " species with internal registry names:")
    for _, sp in ipairs(badNames) do
      print("  " .. sp)
    end
    print("These may indicate a normalization bug.")
  end

  term.setTextColor(colors.white)
  return
elseif args[1] == "list" then
  local map = stateLoad("template_hashes", {})
  local count = 0
  for _ in pairs(map) do count = count + 1 end
  if count == 0 then
    print("No template hashes learned yet.")
    return
  end
  -- Build set of known valid species for validation
  local knownSpecies = {}
  for _, sp in ipairs(buildSpeciesList()) do knownSpecies[sp] = true end

  term.setTextColor(colors.yellow)
  print("Known templates (" .. count .. "):")
  for hash, species in pairs(map) do
    if knownSpecies[species] then
      term.setTextColor(colors.lime)
      write("  OK  ")
    else
      term.setTextColor(colors.orange)
      write("  ??  ")
    end
    term.setTextColor(colors.white)
    print(species .. "  (" .. hash:sub(1, 12) .. "...)")
  end
  return
elseif args[1] == "clear" then
  local target = args[2]
  if not target then
    printError("Usage: learn clear <species>  — remove entries for a species")
    printError("       learn clear all        — remove all entries")
    return
  end
  local map = stateLoad("template_hashes", {})
  if target == "all" then
    local count = 0
    for _ in pairs(map) do count = count + 1 end
    if count == 0 then
      print("Nothing to clear.")
      return
    end
    stateSave("template_hashes", {})
    term.setTextColor(colors.yellow)
    print("Cleared all " .. count .. " template hash(es).")
    term.setTextColor(colors.white)
  else
    target = titleCase(target)
    local removed = 0
    for hash, species in pairs(map) do
      if species == target then
        map[hash] = nil
        removed = removed + 1
      end
    end
    if removed == 0 then
      printError("No entries found for: " .. target)
    else
      stateSave("template_hashes", map)
      term.setTextColor(colors.yellow)
      print("Removed " .. removed .. " entry/entries for " .. target .. ".")
      term.setTextColor(colors.white)
    end
  end
  return
elseif args[1] == "prune" then
  -- Remove entries whose species aren't in the full species list
  local map = stateLoad("template_hashes", {})
  local knownSpecies = {}
  for _, sp in ipairs(buildSpeciesList()) do knownSpecies[sp] = true end
  local removed = 0
  for hash, species in pairs(map) do
    if not knownSpecies[species] then
      term.setTextColor(colors.orange)
      print("  Removing: " .. species .. " (" .. hash:sub(1, 12) .. "...)")
      map[hash] = nil
      removed = removed + 1
    end
  end
  if removed > 0 then
    stateSave("template_hashes", map)
    term.setTextColor(colors.yellow)
    print("Pruned " .. removed .. " invalid entry/entries.")
  else
    term.setTextColor(colors.lime)
    print("All entries are valid.")
  end
  term.setTextColor(colors.white)
  return
elseif #args >= 1 then
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
