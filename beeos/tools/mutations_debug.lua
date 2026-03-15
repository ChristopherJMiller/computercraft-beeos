-- BeeOS Mutation Debug Tool
-- Run this on the computer connected to a Forestry Analyzer to diagnose
-- getMutationsList errors.

print("=== Mutation Debug Tool ===")
print()

-- Step 1: Find peripherals with mutation methods
print("[1] Searching for peripherals with mutation methods...")
local found = {}
for _, name in ipairs(peripheral.getNames()) do
  local methods = peripheral.getMethods(name)
  if methods then
    for _, m in ipairs(methods) do
      if m:find("utation") or m:find("pecies") then
        if not found[name] then
          found[name] = {}
        end
        found[name][#found[name] + 1] = m
      end
    end
  end
end

if not next(found) then
  print("  ERROR: No peripherals found with mutation/species methods!")
  print("  Make sure a Forestry Analyzer is connected via wired modem.")
  return
end

for name, methods in pairs(found) do
  print("  " .. name .. ":")
  for _, m in ipairs(methods) do
    print("    - " .. m)
  end
end
print()

-- Step 2: Try each method on the first analyzer found
local analyzerName = next(found)
local analyzer = peripheral.wrap(analyzerName)
print("[2] Testing methods on: " .. analyzerName)
print()

-- Test getSpeciesRoots
print("[2a] getSpeciesRoots()...")
local ok, result = pcall(analyzer.getSpeciesRoots)
if ok then
  print("  OK! Species roots:")
  if type(result) == "table" then
    for k, v in pairs(result) do
      print("    " .. tostring(k) .. " = " .. tostring(v))
    end
  else
    print("  " .. tostring(result))
  end
else
  print("  FAILED: " .. tostring(result))
end
print()

-- Test getSpeciesList
print("[2b] getSpeciesList('rootBees')...")
ok, result = pcall(analyzer.getSpeciesList, "rootBees")
if ok then
  local count = 0
  if type(result) == "table" then
    for _ in pairs(result) do count = count + 1 end
  end
  print("  OK! Got " .. count .. " species")
  -- Show first 3
  if type(result) == "table" then
    local shown = 0
    for i, sp in ipairs(result) do
      if shown >= 3 then
        print("  ... and " .. (count - 3) .. " more")
        break
      end
      if type(sp) == "table" then
        print("  [" .. i .. "] id=" .. tostring(sp.id) ..
          " name=" .. tostring(sp.displayName))
      else
        print("  [" .. i .. "] " .. tostring(sp))
      end
      shown = shown + 1
    end
  end
else
  print("  FAILED: " .. tostring(result))
end
print()

-- Test getMutationsList - the one that's failing
print("[2c] getMutationsList('rootBees')...")
ok, result = pcall(analyzer.getMutationsList, "rootBees")
if ok then
  local count = 0
  if type(result) == "table" then
    for _ in pairs(result) do count = count + 1 end
  end
  print("  OK! Got " .. count .. " mutations")
  -- Show first 3
  if type(result) == "table" then
    local shown = 0
    for i, mut in ipairs(result) do
      if shown >= 3 then
        print("  ... and " .. (count - 3) .. " more")
        break
      end
      print("  [" .. i .. "] " .. tostring(mut.species1) ..
        " + " .. tostring(mut.species2) ..
        " = chance:" .. tostring(mut.chance))
      if type(mut.result) == "table" and type(mut.result.species) == "table" then
        print("       -> " .. tostring(mut.result.species.displayName))
      end
      shown = shown + 1
    end
  end
else
  print("  FAILED: " .. tostring(result))
  print()
  print("  Full error:")
  print("  " .. tostring(result))
end
print()

-- Step 3: If getMutationsList failed, try alternate approaches
if not ok then
  print("[3] Trying alternate root UIDs...")
  local roots = {}
  local rok, rres = pcall(analyzer.getSpeciesRoots)
  if rok and type(rres) == "table" then
    for _, v in pairs(rres) do
      roots[#roots + 1] = tostring(v)
    end
  end

  for _, root in ipairs(roots) do
    print("  Trying getMutationsList('" .. root .. "')...")
    local ok2, res2 = pcall(analyzer.getMutationsList, root)
    if ok2 then
      local c = 0
      if type(res2) == "table" then
        for _ in pairs(res2) do c = c + 1 end
      end
      print("    OK! Got " .. c .. " mutations")
    else
      print("    FAILED: " .. tostring(res2):sub(1, 80))
    end
  end
end

print()
print("=== Debug complete ===")
