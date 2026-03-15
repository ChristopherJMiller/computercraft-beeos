-- BeeOS Network Manager
-- Auto-discovers and categorizes peripherals on the wired network.

local network = {}

-- Peripheral categories and their detection patterns
local PATTERNS = {
  apiary = { "industrial_apiary", "apiary" },
  sampler = { "sampler" },
  imprinter = { "imprinter" },
  mutatron = { "mutatron" },
  transposer = { "transposer" },
  dnaExtractor = { "extractor", "dna_extractor" },
  analyzer = { "analyzer" },
  turtle = { "turtle" },
  chest = { "chest", "barrel", "crate", "shulker" },
}

--- Categorize a peripheral name/type into a BeeOS category.
-- @param name Peripheral name
-- @param pType Peripheral type
-- @return Category string or nil
local function categorize(name, pType)
  local lower = (name .. " " .. pType):lower()
  for category, patterns in pairs(PATTERNS) do
    for _, pattern in ipairs(patterns) do
      if lower:find(pattern) then
        return category
      end
    end
  end
  return nil
end

--- Scan the network and return categorized peripherals.
-- @return Table of { category = { [name] = wrappedPeripheral, ... }, ... }
function network.scan()
  local result = {}
  for category in pairs(PATTERNS) do
    result[category] = {}
  end
  result.other = {}

  for _, name in ipairs(peripheral.getNames()) do
    local pType = peripheral.getType(name)
    local category = categorize(name, pType)
    local wrapped = peripheral.wrap(name)

    if category then
      result[category][name] = wrapped
    else
      result.other[name] = wrapped
    end
  end

  return result
end

--- Build a detailed summary string of all categorized machines.
-- @param machines Table from network.scan()
-- @return string Summary listing each category and its peripheral names
function network.detailedSummary(machines)
  local categories = {
    "apiary", "sampler", "imprinter", "mutatron",
    "transposer", "dnaExtractor", "analyzer", "turtle",
  }
  local parts = {}
  for _, cat in ipairs(categories) do
    local names = {}
    for name in pairs(machines[cat] or {}) do
      names[#names + 1] = name
    end
    if #names > 0 then
      table.sort(names)
      parts[#parts + 1] = cat .. ": " .. table.concat(names, ", ")
    end
  end
  return #parts > 0 and table.concat(parts, "; ") or "No machines found"
end

--- Count peripherals in a category.
-- @param machines Table from network.scan()
-- @param category Category string
-- @return number
function network.count(machines, category)
  local n = 0
  for _ in pairs(machines[category] or {}) do
    n = n + 1
  end
  return n
end

--- Get the first peripheral in a category.
-- @param machines Table from network.scan()
-- @param category Category string
-- @return name, peripheral or nil, nil
function network.first(machines, category)
  local name = next(machines[category] or {})
  if name then
    return name, machines[category][name]
  end
  return nil, nil
end

--- Find a peripheral that has a specific method.
-- Uses peripheral.getMethods() for reliable detection (avoids Plethora
-- metatable proxies that return non-nil for any method name).
-- @param method Method name to look for
-- @return name, peripheral or nil, nil
function network.findWithMethod(method)
  for _, name in ipairs(peripheral.getNames()) do
    local methods = peripheral.getMethods(name)
    if methods then
      for _, m in ipairs(methods) do
        if m == method then
          return name, peripheral.wrap(name)
        end
      end
    end
  end
  return nil, nil
end

--- Get a named peripheral, with a friendly error if missing.
-- @param name Peripheral name from config
-- @return Wrapped peripheral
-- @error If peripheral not found
function network.require(name)
  local p = peripheral.wrap(name)
  if not p then
    error("Required peripheral not found: " .. name .. "\nCheck wired modem connections and config.lua")
  end
  return p
end

--- Print a summary of discovered machines.
-- @param machines Table from network.scan()
function network.printSummary(machines)
  local categories = {
    "apiary", "sampler", "imprinter", "mutatron",
    "transposer", "dnaExtractor", "analyzer", "turtle", "chest",
  }
  for _, cat in ipairs(categories) do
    local count = network.count(machines, cat)
    if count > 0 then
      print(string.format("  %s: %d", cat, count))
      for name in pairs(machines[cat]) do
        print("    - " .. name)
      end
    end
  end
end

return network
