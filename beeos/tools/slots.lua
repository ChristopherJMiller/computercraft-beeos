-- BeeOS Slot Mapper
-- Enumerates all slots in a machine and shows what's in each one.
-- Use this to discover input/output/upgrade slot numbers for each machine type.
--
-- Usage: slots <peripheral_name>
--   Example: slots gendustry:industrial_apiary_0

local args = { ... }

if #args < 1 then
  print("Usage: slots <peripheral_name>")
  print("  Maps all inventory slots of a machine.")
  print()
  print("Available peripherals:")
  for _, name in ipairs(peripheral.getNames()) do
    local p = peripheral.wrap(name)
    if p.size or p.getInventorySize then
      print("  " .. name)
    end
  end
  return
end

local periName = args[1]
local p = peripheral.wrap(periName)
if not p then
  printError("Peripheral not found: " .. periName)
  return
end

-- Get inventory size
local size
if p.size then
  size = p.size()
elseif p.getInventorySize then
  size = p.getInventorySize()
else
  printError("Peripheral is not an inventory (no size/getInventorySize method)")
  return
end

local pType = peripheral.getType(periName)

term.setTextColor(colors.yellow)
print("=== Slot Map: " .. periName .. " ===")
print("Type: " .. pType)
print("Slots: " .. size)
print(string.rep("-", 50))
term.setTextColor(colors.white)

local occupied = 0
for slot = 1, size do
  local meta
  if p.getItemMeta then
    meta = p.getItemMeta(slot)
  elseif p.getItemDetail then
    meta = p.getItemDetail(slot)
  end

  if meta then
    occupied = occupied + 1
    term.setTextColor(colors.lime)
    write(string.format("  Slot %2d: ", slot))
    term.setTextColor(colors.white)
    local display = meta.displayName or meta.name or "unknown"
    local count = meta.count or 1
    print(display .. " x" .. count)

    -- Extra info for bees
    if meta.individual and meta.individual.genome then
      local species = meta.individual.genome.active.species
      if species then
        term.setTextColor(colors.cyan)
        print(string.format("          Species: %s (inactive: %s)",
          species.displayName or "?",
          (meta.individual.genome.inactive.species or {}).displayName or "?"))
        term.setTextColor(colors.white)
      end
    end
  else
    term.setTextColor(colors.lightGray)
    print(string.format("  Slot %2d: (empty)", slot))
    term.setTextColor(colors.white)
  end
end

print()
term.setTextColor(colors.yellow)
print("Summary: " .. occupied .. "/" .. size .. " slots occupied")
term.setTextColor(colors.white)

-- Test item transfer capabilities
print()
term.setTextColor(colors.yellow)
print("=== Transfer Methods ===")
term.setTextColor(colors.white)

local transferMethods = { "pushItems", "pullItems", "getItemMeta", "getItemDetail", "list" }
for _, method in ipairs(transferMethods) do
  local has = p[method] ~= nil
  term.setTextColor(has and colors.lime or colors.red)
  print("  " .. method .. ": " .. (has and "YES" or "NO"))
end

-- For apiaries, check bee-housing methods
if pType:find("apiary") or pType:find("bee") then
  print()
  term.setTextColor(colors.yellow)
  print("=== Bee Housing Methods ===")
  term.setTextColor(colors.white)

  local beeMethods = { "getQueen", "getDrone", "getTemperature", "getHumidity" }
  for _, method in ipairs(beeMethods) do
    local has = p[method] ~= nil
    term.setTextColor(has and colors.lime or colors.red)
    write("  " .. method .. ": " .. (has and "YES" or "NO"))
    if has then
      local ok, result = pcall(p[method])
      if ok and result then
        term.setTextColor(colors.cyan)
        if type(result) == "table" and result.individual then
          write(" → " .. (result.individual.genome.active.species.displayName or "?"))
        else
          write(" → " .. tostring(result))
        end
      end
    end
    print()
  end
end

term.setTextColor(colors.white)
