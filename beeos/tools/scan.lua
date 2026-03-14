-- BeeOS Network Scanner
-- Lists all peripherals on the wired network with their types and methods.
-- Run this first to discover what machines are connected and how CC sees them.

local function printHeader(text)
  local w = term.getSize()
  term.setTextColor(colors.yellow)
  print(string.rep("-", w))
  print(text)
  print(string.rep("-", w))
  term.setTextColor(colors.white)
end

local function main()
  printHeader("BeeOS Network Scanner")

  local names = peripheral.getNames()
  table.sort(names)

  print("Found " .. #names .. " peripheral(s)\n")

  for _, name in ipairs(names) do
    local pType = peripheral.getType(name)
    local methods = peripheral.getMethods(name)
    table.sort(methods)

    term.setTextColor(colors.lime)
    write(name)
    term.setTextColor(colors.lightGray)
    print("  [" .. pType .. "]")

    -- Categorize for BeeOS relevance
    term.setTextColor(colors.cyan)
    local lower = name:lower()
    if lower:find("apiary") or lower:find("industrial_apiary") then
      print("  >> APIARY")
    elseif lower:find("sampler") then
      print("  >> GENETIC SAMPLER")
    elseif lower:find("imprinter") then
      print("  >> GENETIC IMPRINTER")
    elseif lower:find("mutatron") then
      print("  >> MUTATRON")
    elseif lower:find("extractor") or lower:find("dna") then
      print("  >> DNA EXTRACTOR")
    elseif lower:find("analyzer") then
      print("  >> ANALYZER (mutation queries)")
    elseif lower:find("chest") or lower:find("barrel") or lower:find("crate") then
      print("  >> STORAGE")
    end

    -- Print methods (compact)
    term.setTextColor(colors.lightGray)
    local methodStr = "  Methods: " .. table.concat(methods, ", ")
    if #methodStr > 200 then
      methodStr = methodStr:sub(1, 197) .. "..."
    end
    print(methodStr)
    print()
  end

  -- Summary
  printHeader("Summary by Type")
  local byType = {}
  for _, name in ipairs(names) do
    local pType = peripheral.getType(name)
    byType[pType] = (byType[pType] or 0) + 1
  end

  local types = {}
  for t in pairs(byType) do types[#types + 1] = t end
  table.sort(types)

  for _, t in ipairs(types) do
    print("  " .. byType[t] .. "x " .. t)
  end

  -- Check for Forestry Analyzer (needed for mutation queries)
  print()
  local hasAnalyzer = false
  for _, name in ipairs(names) do
    local p = peripheral.wrap(name)
    if p.getMutationsList then
      hasAnalyzer = true
      term.setTextColor(colors.lime)
      print("Mutation queries available via: " .. name)
      break
    end
  end
  if not hasAnalyzer then
    term.setTextColor(colors.orange)
    print("WARNING: No peripheral with getMutationsList() found.")
    print("Place a Forestry Analyzer on the wired network for Layer 3.")
  end

  term.setTextColor(colors.white)
end

main()
