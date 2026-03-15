-- BeeOS Mutation Debug Tool
-- Tests each Plethora/Forestry method per species root.
-- Full errors written to beeos_mutations_error.log.

print("=== Mutation Debug ===")

-- 1. Find analyzer
print("1. Scanning...")
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
  print("  No analyzer found!")
  return
end
print("  " .. analyzerName)

-- 2. Get roots
print("2. getSpeciesRoots()")
local ok, roots = pcall(analyzer.getSpeciesRoots)
if not ok then
  print("  FAIL: " .. tostring(roots))
  return
end

local rootList = {}
for _, v in pairs(roots) do
  rootList[#rootList + 1] = tostring(v)
end
table.sort(rootList)
print("  " .. #rootList .. " roots")

-- 3. Test getMutationsList per root
print("3. getMutationsList:")
local logLines = { "=== Mutation Debug Log ===" }
logLines[#logLines + 1] = "Analyzer: " .. analyzerName

for i, root in ipairs(rootList) do
  local ok2, res = pcall(analyzer.getMutationsList, root)
  if ok2 then
    local count = 0
    if type(res) == "table" then
      for _ in pairs(res) do count = count + 1 end
    end
    term.setTextColor(colors.lime)
    print("  3." .. i .. " " .. root .. ": " .. count)
    logLines[#logLines + 1] = root .. ": OK (" .. count .. ")"
  else
    local err = tostring(res)
    term.setTextColor(colors.red)
    print("  3." .. i .. " " .. root .. ": FAIL")
    term.setTextColor(colors.orange)
    -- Show truncated on terminal
    print("    " .. err:sub(1, 45))
    if #err > 45 then print("    " .. err:sub(46, 90)) end
    if #err > 90 then print("    " .. err:sub(91, 135)) end
    if #err > 135 then print("    ...see log file") end
    logLines[#logLines + 1] = root .. ": FAILED"
    logLines[#logLines + 1] = "  " .. err
    logLines[#logLines + 1] = ""
  end
end
term.setTextColor(colors.white)

-- 4. Species list check
print("4. getSpeciesList('rootBees')")
local ok3, species = pcall(analyzer.getSpeciesList, "rootBees")
if ok3 then
  local count = 0
  if type(species) == "table" then
    for _ in pairs(species) do count = count + 1 end
  end
  print("  " .. count .. " species")
else
  print("  FAIL: " .. tostring(species):sub(1, 60))
end

-- Write log file
local f = fs.open("beeos_mutations_error.log", "w")
if f then
  f.write(table.concat(logLines, "\n"))
  f.close()
end
print("")
print("Full errors: beeos_mutations_error.log")
print("Run: edit beeos_mutations_error.log")
