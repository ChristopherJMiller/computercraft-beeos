-- BeeOS Mutation Debug Tool
-- Outputs to monitor (if available) for more space.
-- Tests each Plethora/Forestry method to diagnose getMutationsList errors.

-- Set up output: use monitor if available, fall back to terminal
local out = term
for _, name in ipairs(peripheral.getNames()) do
  if peripheral.getType(name) == "monitor" then
    local mon = peripheral.wrap(name)
    mon.setTextScale(0.5)
    mon.clear()
    mon.setCursorPos(1, 1)
    out = mon
    print("Output on monitor: " .. name)
    break
  end
end

local line = 0
local function log(text, color)
  line = line + 1
  out.setCursorPos(1, line)
  if color and out.setTextColor then out.setTextColor(color) end
  out.write(text or "")
  if out == term then print() end  -- terminal needs newline
end

log("=== Mutation Debug ===", colors.yellow)
log("")

-- 1. Find analyzer peripheral
log("1. Scanning peripherals...", colors.white)
local analyzerName, analyzer
for _, name in ipairs(peripheral.getNames()) do
  local methods = peripheral.getMethods(name)
  if methods then
    for _, m in ipairs(methods) do
      if m == "getMutationsList" then
        analyzerName = name
        analyzer = peripheral.wrap(name)
        break
      end
    end
  end
  if analyzer then break end
end

if not analyzer then
  log("   NO analyzer with getMutationsList!", colors.red)
  log("   Connect Forestry Analyzer via modem", colors.lightGray)
  return
end
log("   Found: " .. analyzerName, colors.lime)
log("")

-- 2. Get species roots
log("2. getSpeciesRoots()", colors.white)
local ok, roots = pcall(analyzer.getSpeciesRoots)
if not ok then
  log("   FAIL: " .. tostring(roots), colors.red)
  return
end

local rootList = {}
if type(roots) == "table" then
  for _, v in pairs(roots) do
    rootList[#rootList + 1] = tostring(v)
  end
end
table.sort(rootList)
log("   OK: " .. #rootList .. " roots", colors.lime)
log("")

-- 3. Test getMutationsList on each root
log("3. getMutationsList per root:", colors.white)
for i, root in ipairs(rootList) do
  local ok2, res = pcall(analyzer.getMutationsList, root)
  if ok2 then
    local count = 0
    if type(res) == "table" then
      for _ in pairs(res) do count = count + 1 end
    end
    log("   3." .. i .. " " .. root .. ": OK (" .. count .. ")", colors.lime)
  else
    local err = tostring(res)
    log("   3." .. i .. " " .. root .. ": FAIL", colors.red)
    -- Print error across multiple lines (monitor has width limits)
    local maxW = 50
    while #err > 0 do
      log("      " .. err:sub(1, maxW), colors.orange)
      err = err:sub(maxW + 1)
    end
  end
end
log("")

-- 4. Test getSpeciesList on rootBees specifically
log("4. getSpeciesList('rootBees')", colors.white)
local ok3, species = pcall(analyzer.getSpeciesList, "rootBees")
if ok3 then
  local count = 0
  if type(species) == "table" then
    for _ in pairs(species) do count = count + 1 end
  end
  log("   OK: " .. count .. " species", colors.lime)
  -- Show first 5
  if type(species) == "table" then
    for j = 1, math.min(5, #species) do
      local sp = species[j]
      if type(sp) == "table" then
        log("   [" .. j .. "] " .. tostring(sp.displayName or sp.id or "?"), colors.lightGray)
      else
        log("   [" .. j .. "] " .. tostring(sp), colors.lightGray)
      end
    end
    if count > 5 then
      log("   ... " .. (count - 5) .. " more", colors.lightGray)
    end
  end
else
  log("   FAIL: " .. tostring(species), colors.red)
end
log("")

-- 5. Also write full error to file for copy-paste
log("5. Full errors written to:", colors.white)
log("   beeos_mutations_error.log", colors.cyan)

local f = fs.open("beeos_mutations_error.log", "w")
if f then
  f.write("=== Mutation Debug Log ===\n")
  f.write("Analyzer: " .. analyzerName .. "\n")
  f.write("Roots: " .. table.concat(rootList, ", ") .. "\n\n")

  for _, root in ipairs(rootList) do
    local ok4, res = pcall(analyzer.getMutationsList, root)
    if ok4 then
      local count = 0
      if type(res) == "table" then
        for _ in pairs(res) do count = count + 1 end
      end
      f.write(root .. ": OK (" .. count .. " mutations)\n")
    else
      f.write(root .. ": FAILED\n")
      f.write("  " .. tostring(res) .. "\n\n")
    end
  end
  f.close()
end

log("")
log("=== Done ===", colors.yellow)
