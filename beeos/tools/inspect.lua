-- BeeOS Bee Inspector
-- Reads and displays full genetic data from a bee (or gene sample/template)
-- in a specified inventory slot.
--
-- Usage: inspect <peripheral_name> [slot]
--   slot defaults to 1 if not specified
--   Example: inspect minecraft:chest_0 1

local args = { ... }

if #args < 1 then
  print("Usage: inspect <peripheral_name> [slot]")
  print("  Reads bee genetics or gene sample data from an inventory slot.")
  print("  Example: inspect minecraft:chest_0 1")
  print()
  print("Available inventories:")
  for _, name in ipairs(peripheral.getNames()) do
    local p = peripheral.wrap(name)
    if p.getItemMeta or p.getItemDetail then
      print("  " .. name)
    end
  end
  return
end

local periName = args[1]
local slot = tonumber(args[2]) or 1

local p = peripheral.wrap(periName)
if not p then
  printError("Peripheral not found: " .. periName)
  return
end

-- Try Plethora's getItemMeta first, fall back to CC's getItemDetail
local meta
if p.getItemMeta then
  meta = p.getItemMeta(slot)
elseif p.getItemDetail then
  meta = p.getItemDetail(slot)
else
  printError("Peripheral has no item inspection methods")
  return
end

if not meta then
  print("Slot " .. slot .. " is empty.")
  return
end

-- Pretty-print a table with indentation
local function dump(tbl, indent)
  indent = indent or 0
  local pad = string.rep("  ", indent)

  if type(tbl) ~= "table" then
    print(pad .. tostring(tbl))
    return
  end

  -- Sort keys for consistent output
  local keys = {}
  for k in pairs(tbl) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)

  for _, k in ipairs(keys) do
    local v = tbl[k]
    if type(v) == "table" then
      term.setTextColor(colors.cyan)
      print(pad .. tostring(k) .. ":")
      term.setTextColor(colors.white)
      dump(v, indent + 1)
    else
      term.setTextColor(colors.cyan)
      write(pad .. tostring(k) .. ": ")
      if type(v) == "boolean" then
        term.setTextColor(v and colors.lime or colors.red)
      elseif type(v) == "number" then
        term.setTextColor(colors.orange)
      else
        term.setTextColor(colors.white)
      end
      print(tostring(v))
    end
  end
  term.setTextColor(colors.white)
end

-- Header
term.setTextColor(colors.yellow)
print("=== Item in " .. periName .. " slot " .. slot .. " ===")
term.setTextColor(colors.white)
print("Name: " .. (meta.name or meta.id or "unknown"))
print("Display: " .. (meta.displayName or "unknown"))
print("Count: " .. (meta.count or 1))
print()

-- Check if it's a bee
if meta.individual then
  term.setTextColor(colors.yellow)
  print("=== BEE GENETICS ===")
  term.setTextColor(colors.white)

  local ind = meta.individual
  print("Analyzed: " .. tostring(ind.isAnalyzed))

  if ind.genome then
    print()
    term.setTextColor(colors.lime)
    print("--- Active Alleles ---")
    term.setTextColor(colors.white)
    dump(ind.genome.active, 1)

    print()
    term.setTextColor(colors.orange)
    print("--- Inactive Alleles ---")
    term.setTextColor(colors.white)
    dump(ind.genome.inactive, 1)
  end

  if ind.bee then
    print()
    term.setTextColor(colors.yellow)
    print("--- Bee Info ---")
    term.setTextColor(colors.white)
    dump(ind.bee, 1)
  end
else
  -- Not a bee - dump everything for inspection (gene samples, templates, etc.)
  term.setTextColor(colors.yellow)
  print("=== FULL ITEM DATA ===")
  term.setTextColor(colors.white)
  dump(meta, 1)
end

-- Also dump raw data to a file for offline analysis
local filename = "inspect_dump_" .. periName:gsub("[:/]", "_") .. "_" .. slot .. ".txt"
local f = fs.open(filename, "w")
f.write(textutils.serialise(meta))
f.close()
term.setTextColor(colors.lightGray)
print("\nFull data saved to: " .. filename)
term.setTextColor(colors.white)
