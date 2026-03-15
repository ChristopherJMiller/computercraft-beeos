-- BeeOS - ComputerCraft Bee Automation System
-- Main orchestrator: runs all layers in parallel with error recovery.

local config = require("config")
local network = require("lib.network")
local tracker = require("lib.tracker")
local apiary = require("lib.apiary")
local sampler = require("lib.sampler")
local discovery = require("lib.discovery")
local surplus = require("lib.surplus")
local traitExport = require("lib.trait_export")
local mutations = require("lib.mutations")
local imprinter = require("lib.imprinter")
local analyzer = require("lib.analyzer")
local inventory = require("lib.inventory")
local display = require("lib.display")
local state = require("lib.state")
local updater = require("lib.updater")

-- Configurable keys (section.key format)
local CONFIGURABLE = {
  ["chests.droneBuffer"]     = "Drone buffer chest",
  ["chests.sampleStorage"]   = "Sample storage chest",
  ["chests.export"]          = "Export chest (AE2 import: combs, surplus, waste)",
  ["chests.templateOutput"]  = "Template output chest (AE2 import)",
  ["chests.supplyInput"]     = "Supply input chest (AE2 export)",
  ["chests.princessStorage"] = "Princess overflow chest",
  ["chests.traitTemplates"]  = "Trait template chest (pre-stocked for imprinter)",
  ["chests.discoveryStaging"] = "Discovery staging chest (imprinted bees between steps)",
  ["chests.productOutput"]   = "Legacy product output (use export instead)",
  ["chests.surplusOutput"]   = "Legacy surplus output (use export instead)",
}

-- Config keys that support multi-chest arrays (use +/- syntax)
local MULTI_CHEST_KEYS = {
  ["chests.droneBuffer"] = true,
  ["chests.sampleStorage"] = true,
  ["chests.export"] = true,
  ["chests.templateOutput"] = true,
  ["chests.supplyInput"] = true,
  ["chests.princessStorage"] = true,
  ["chests.traitTemplates"] = true,
  ["chests.discoveryStaging"] = true,
  ["chests.productOutput"] = true,
  ["chests.surplusOutput"] = true,
  ["machines.transposers"]   = "Genetic transposer peripherals",
  ["machines.analyzer"]      = "Forestry analyzer peripheral",
  ["mutations.preset"]       = "Mutation data preset (e.g., meatballcraft)",
  ["turtle.name"]            = "Crafting turtle peripheral",
  ["display.monitorSide"]    = "Monitor peripheral name",
  ["thresholds.minSamplesPerSpecies"] = "Min gene samples per species",
  ["thresholds.minDronesPerSpecies"]  = "Min drones to keep per species",
  ["thresholds.maxDronesPerSpecies"]  = "Max drones before surplus",
  ["discovery.maxConcurrentMutations"] = "Max concurrent mutations",
}

--- Load config overrides from persistent state and merge into config.
local function loadConfigOverrides()
  local overrides = state.load("config_overrides", {})
  for section, values in pairs(overrides) do
    if type(config[section]) == "table" and type(values) == "table" then
      for k, v in pairs(values) do
        config[section][k] = v
      end
    end
  end
end

--- Save a config override (dot path, e.g. "chests.droneBuffer").
-- @param path Dot-separated path
-- @param value Value to set (nil to clear)
local function saveConfigOverride(path, value)
  local section, key = path:match("^(%w+)%.(%w+)$")
  if not section or not key then return false end
  if not config[section] then return false end

  -- Apply to running config
  config[section][key] = value

  -- Save to persistent overrides
  local overrides = state.load("config_overrides", {})
  if not overrides[section] then
    overrides[section] = {}
  end
  if value == nil then
    overrides[section][key] = nil
    -- Clean up empty sections
    if not next(overrides[section]) then
      overrides[section] = nil
    end
  else
    overrides[section][key] = value
  end
  state.save("config_overrides", overrides)
  return true
end

--- Format a config value for terminal display.
local function formatConfigValue(path, val)
  if val == nil then return "<not set>" end
  if type(val) == "table" then
    if #val == 0 then return "<not set>" end
    return table.concat(val, ", ")
  end
  return tostring(val)
end

--- Get a config value by dot path.
local function getConfigValue(path)
  local section, key = path:match("^(%w+)%.(%w+)$")
  if section and key and config[section] then
    return config[section][key]
  end
  return nil
end

-- Runtime state
local running = true
local machines = {}

--- Rescan the network for machines.
local function rescanNetwork()
  local ok, result = pcall(network.scan)
  if ok then
    machines = result
    tracker.addLog("Network scan: " ..
      network.count(machines, "apiary") .. " apiaries, " ..
      network.count(machines, "sampler") .. " samplers, " ..
      network.count(machines, "transposer") .. " transposers, " ..
      network.count(machines, "mutatron") .. " mutatrons")
    tracker.addLog("Machines: " .. network.detailedSummary(machines))
  else
    tracker.addLog("Network scan FAILED: " .. tostring(result))
  end
  -- Sync display immediately so the monitor reflects the new state
  display.machines = machines
end

--- Layer 0: Passive Tracker loop
local function trackerLoop()
  -- restore() and initial scan already done in boot sequence
  local lastSpecies, lastItems, lastInvs = -1, -1, -1
  while running do
    if config.layers.tracker then
      local ok, invCount, itemCount = pcall(tracker.scan, machines)
      if ok then
        local stats = tracker.stats()
        if stats.discovered ~= lastSpecies or itemCount ~= lastItems
            or invCount ~= lastInvs then
          tracker.addLog("Tracker: " .. stats.discovered .. " species, " ..
            (itemCount or 0) .. " items in " .. (invCount or 0) .. " inventories")
          lastSpecies = stats.discovered
          lastItems = itemCount
          lastInvs = invCount
        end
      else
        tracker.addLog("Tracker error: " .. tostring(invCount))
      end
    end
    sleep(config.timing.trackerInterval)
  end
end

--- Layer 1: Apiary Manager loop
local function apiaryLoop()
  while running do
    if config.layers.apiary then
      local count = 0
      for name, p in pairs(machines.apiary or {}) do
        count = count + 1
        local ok, err = pcall(apiary.check, name, p, config)
        if not ok then
          tracker.addLog("Apiary error (" .. name .. "): " .. tostring(err))
        end
      end
      if count > 0 then
        tracker.addLog("Apiary: checked " .. count .. " apiaries")
      end
    end
    sleep(config.timing.apiaryInterval)
  end
end

--- Sampler machine collector loop (rapid 0.5s polling)
-- Dedicated coroutine that keeps sampler-layer machines clear.
-- Runs independently of the decision loop so output is collected fast.
local function machineCollectorLoop()
  while running do
    if config.layers.sampler then
      pcall(sampler.collectTransposerOutput, machines, config)
      pcall(sampler.collectOutput, machines, config)
      pcall(sampler.collectFromTurtle, config)
    end
    sleep(0.5)
  end
end

--- Layer 2: Sample & Template Manager loop (decision-only)
-- Routes drones, starts duplication, requests templates.
-- Machine collection is handled by machineCollectorLoop.
local function samplerLoop()
  while running do
    if config.layers.sampler then
      local ok, err = pcall(sampler.processDrones, machines, config)
      if not ok then
        tracker.addLog("Sampler error: " .. tostring(err))
      end

      -- Duplicate samples via transposer for species below threshold
      if sampler.hasTransposer(machines, config) then
        local bestSpecies, bestCount = nil, math.huge
        for species, data in pairs(tracker.catalog) do
          if data.samples >= 1
              and data.samples < (config.thresholds.minSamplesPerSpecies or 3) then
            if data.samples < bestCount then
              bestSpecies = species
              bestCount = data.samples
            end
          end
        end
        if bestSpecies then
          ok, err = pcall(sampler.duplicateSample, bestSpecies, machines, config)
          if not ok then
            tracker.addLog("Transposer error: " .. tostring(err))
          end
        end
      end

      -- Check if any species need templates
      for species, data in pairs(tracker.catalog) do
        if data.samples >= 1 and data.templates == 0 then
          pcall(sampler.requestTemplate, species, machines, config)
        end
      end
    end
    sleep(config.timing.samplerInterval)
  end
end

--- Layer 3: Auto-Discovery loop
local function discoveryLoop()
  -- Load mutation graph
  local loaded = false
  local loadAttempts = 0

  while running do
    if config.layers.discovery then
      -- Load mutation graph on first enable
      if not loaded then
        loadAttempts = loadAttempts + 1
        local ok, err = mutations.load(config.machines.analyzer,
          config.mutations and config.mutations.preset)
        if ok then
          loaded = true
          tracker.allSpecies = mutations.allSpecies
          discovery.init()
          tracker.addLog("Mutations loaded (" .. (mutations.source or "?") ..
            "): " .. #mutations.allSpecies .. " species")
        else
          -- Only log first failure and then every 10th retry
          if loadAttempts == 1 or loadAttempts % 10 == 0 then
            tracker.addLog("Cannot load mutations (attempt " ..
              loadAttempts .. "): " .. tostring(err))
          end
        end
      end

      if loaded then
        -- Sync discovered set with tracker catalog
        for species in pairs(tracker.catalog) do
          discovery.markDiscovered(species)
        end

        -- Check bootstrap queue and clear established species
        local queue = discovery.getBootstrapQueue()
        for species in pairs(queue) do
          local entry = tracker.catalog[species]
          if entry and entry.samples >= 1 and entry.templates >= 1 then
            discovery.removeBootstrap(species)
          end
        end

        local ok, err = pcall(discovery.tick, machines, config)
        if not ok then
          tracker.addLog("Discovery error: " .. tostring(err))
        end
      end
    end
    if discovery.state ~= "idle" then
      sleep(1)
    else
      sleep(config.timing.discoveryInterval)
    end
  end
end

--- Trait imprinting loop
local function imprinterLoop()
  while running do
    if config.layers.apiary then
      local ok, err = pcall(imprinter.tick, machines, config)
      if not ok then
        tracker.addLog("Imprinter error: " .. tostring(err))
      end
    end
    imprinter.pollActive(machines, config, config.timing.apiaryInterval)
  end
end

--- Bee analysis loop
local function analyzerLoop()
  while running do
    if config.layers.apiary then
      local ok, err = pcall(analyzer.tick, machines, config)
      if not ok then
        tracker.addLog("Analyzer error: " .. tostring(err))
      end
    end
    sleep(config.timing.apiaryInterval)
  end
end

--- Surplus management loop
local function surplusLoop()
  while running do
    if config.layers.surplus then
      local ok, err = pcall(surplus.process, machines, config)
      if not ok then
        tracker.addLog("Surplus error: " .. tostring(err))
      end

      ok, err = pcall(surplus.feedExtractor, machines, config)
      if not ok then
        tracker.addLog("Extractor feed error: " .. tostring(err))
      end
    end
    sleep(config.timing.samplerInterval)
  end
end

--- Layer 5: Trait sample export loop
local function traitExportLoop()
  while running do
    if config.layers.traitExport then
      local ok, err = pcall(traitExport.process, machines, config)
      if not ok then
        tracker.addLog("Trait export error: " .. tostring(err))
      end
    end
    sleep(config.timing.samplerInterval)
  end
end

--- Display refresh loop
local function displayLoop()
  -- display.init() already called in boot sequence
  while running do
    -- Sync references each frame (machines table may be replaced by rescan)
    display.machines = machines

    -- Sync layer states to display
    display.layerStates = {
      tracker = config.layers.tracker,
      apiary = config.layers.apiary,
      sampler = config.layers.sampler,
      discovery = config.layers.discovery,
      surplus = config.layers.surplus,
      traitExport = config.layers.traitExport,
    }

    local ok, err = pcall(display.render)
    if not ok then
      tracker.addLog("Display error: " .. tostring(err))
    end

    sleep(config.display.refreshRate)
  end
end

--- Monitor touch event handler
local function touchLoop()
  while running do
    local _, side, x, y = os.pullEvent("monitor_touch")
    if display.monitorName and (side == display.monitorName) then
      local action = display.handleTouch(x, y)
      if action then
        if action.action == "toggle" then
          config.layers[action.layer] = not config.layers[action.layer]
          local layerStatus = config.layers[action.layer] and "ON" or "OFF"
          tracker.addLog("Layer " .. action.layer .. ": " .. layerStatus)
          state.save("layers", config.layers)
        elseif action.action == "rescan" then
          rescanNetwork()
          pcall(display.render)
        elseif action.action == "update" then
          display.updateStatus = "Updating..."
          tracker.addLog("Update started (monitor)")
          local ok2, s, f = pcall(updater.update)
          if ok2 then
            display.updateStatus = s .. " OK, " .. f .. " failed"
            tracker.addLog("Update: " .. s .. " OK, " .. f .. " failed")
          else
            display.updateStatus = "Update failed!"
            tracker.addLog("Update error: " .. tostring(s))
          end
        end
        -- Tab/config changes are handled inside display.handleTouch
      end
    end
  end
end

--- Terminal command handler
local function terminalLoop()
  term.clear()
  term.setCursorPos(1, 1)

  term.setTextColor(colors.yellow)
  print("=== BeeOS v0.1 ===")
  term.setTextColor(colors.white)
  print("Commands: status, enable <layer>, disable <layer>,")
  print("  target <species>, rescan, stop")
  print()

  while running do
    term.setTextColor(colors.lime)
    write("beeos> ")
    term.setTextColor(colors.white)

    local input = read()
    if not input then break end

    local parts = {}
    for word in input:gmatch("%S+") do
      parts[#parts + 1] = word
    end
    local cmd = parts[1]

    if cmd == "stop" or cmd == "quit" or cmd == "exit" then
      running = false
      print("Shutting down (extracting machines)...")

    elseif cmd == "status" then
      local layerInfo = {
        { key = "tracker",   num = 0, name = "Passive Tracker" },
        { key = "apiary",    num = 1, name = "Apiary Manager" },
        { key = "sampler",   num = 2, name = "Sample & Template Manager" },
        { key = "discovery", num = 3, name = "Auto-Discovery" },
        { key = "surplus",      num = 4, name = "Surplus Management" },
        { key = "traitExport", num = 5, name = "Trait Export" },
      }
      print("Layers:")
      for _, info in ipairs(layerInfo) do
        local enabled = config.layers[info.key]
        term.setTextColor(enabled and colors.lime or colors.red)
        print("  L" .. info.num .. " " .. info.name .. ": " .. (enabled and "ON" or "OFF"))
      end
      term.setTextColor(colors.white)

      local stats = tracker.stats()
      print("Species discovered: " .. stats.discovered)
      print("Fully stocked: " .. stats.fullyStocked)
      print("Need attention: " .. stats.needsAttention)
      print("Apiaries: " .. network.count(machines, "apiary"))

    elseif cmd == "enable" and parts[2] then
      local layer = parts[2]
      if config.layers[layer] ~= nil then
        config.layers[layer] = true
        state.save("layers", config.layers)
        print("Enabled: " .. layer)
        tracker.addLog("Layer " .. layer .. ": ON (terminal)")
      else
        print("Unknown layer: " .. layer)
        print("Available: tracker, apiary, sampler, discovery, surplus, traitExport")
      end

    elseif cmd == "disable" and parts[2] then
      local layer = parts[2]
      if config.layers[layer] ~= nil then
        config.layers[layer] = false
        state.save("layers", config.layers)
        print("Disabled: " .. layer)
        tracker.addLog("Layer " .. layer .. ": OFF (terminal)")
      else
        print("Unknown layer: " .. layer)
      end

    elseif cmd == "target" and parts[2] then
      local species = table.concat(parts, " ", 2)
      table.insert(config.discovery.prioritySpecies, 1, species)
      print("Priority target: " .. species)
      tracker.addLog("Manual target: " .. species)

    elseif cmd == "rescan" then
      rescanNetwork()
      pcall(display.render)
      print("Network rescanned.")

    elseif cmd == "species" then
      local sorted = tracker.sortedSpecies()
      for _, sp in ipairs(sorted) do
        term.setTextColor(sp.color)
        print(string.format("  %-20s S:%d T:%d D:%d P:%d",
          sp.name, sp.data.samples, sp.data.templates,
          sp.data.drones, sp.data.princesses))
      end
      term.setTextColor(colors.white)

    elseif cmd == "layers" then
      local layerDescs = {
        { num = 0, key = "tracker",   name = "Passive Tracker",
          desc = "Scans all inventories and catalogs every bee"
            .. " species, tracking drones, princesses, samples,"
            .. " and templates." },
        { num = 1, key = "apiary",    name = "Apiary Manager",
          desc = "Manages industrial apiaries: loads princesses"
            .. " and drones, collects products, restarts stalled"
            .. " breeding." },
        { num = 2, key = "sampler",   name = "Sample & Template Manager",
          desc = "Routes drones to the Genetic Sampler, duplicates"
            .. " samples via Transposer, crafts templates via"
            .. " turtle." },
        { num = 3, key = "discovery", name = "Auto-Discovery",
          desc = "Loads the mutation graph, finds undiscovered"
            .. " species, and breeds them in the Mutatron"
            .. " automatically." },
        { num = 4, key = "surplus", name = "Surplus Management",
          desc = "Routes excess drones to the DNA Extractor"
            .. " and manages surplus inventory above configured"
            .. " thresholds." },
        { num = 5, key = "traitExport", name = "Trait Export",
          desc = "Exports non-species genetic samples (trait"
            .. " samples like speed, lifespan, cave dwelling)"
            .. " from sample storage to the export chest." },
      }
      for _, l in ipairs(layerDescs) do
        local enabled = config.layers[l.key]
        term.setTextColor(colors.yellow)
        write("  L" .. l.num .. " " .. l.name)
        term.setTextColor(enabled and colors.lime or colors.red)
        print(" [" .. (enabled and "ON" or "OFF") .. "]")
        term.setTextColor(colors.lightGray)
        print("     " .. l.desc)
        print()
      end
      term.setTextColor(colors.white)

    elseif cmd == "log" then
      for i = 1, math.min(10, #tracker.log) do
        local entry = tracker.log[i]
        print("  " .. (entry.message or ""))
      end

    elseif cmd == "config" then
      if not parts[2] then
        -- Show all configurable settings
        print("Configuration (use 'config <key> <value>' to set):")
        local sections = {}
        for path in pairs(CONFIGURABLE) do
          local section = path:match("^(%w+)%.")
          if not sections[section] then
            sections[section] = {}
            sections[section]._order = section
          end
          sections[section][#sections[section] + 1] = path
        end
        for _, paths in pairs(sections) do
          table.sort(paths)
          for _, path in ipairs(paths) do
            local val = getConfigValue(path)
            local display_val = formatConfigValue(path, val)
            local hasVal = val ~= nil and (type(val) ~= "table" or #val > 0)
            term.setTextColor(hasVal and colors.lime or colors.lightGray)
            print(string.format("  %-38s %s", path, display_val))
          end
        end
        term.setTextColor(colors.white)

      elseif parts[2] == "clear" and parts[3] then
        -- Clear an override
        local path = parts[3]
        if CONFIGURABLE[path] then
          saveConfigOverride(path, nil)
          print("Cleared: " .. path)
          tracker.addLog("Config cleared: " .. path)
        else
          print("Unknown key: " .. path)
        end

      elseif parts[3] then
        -- Set a value
        local path = parts[2]
        if CONFIGURABLE[path] then
          local rawValue = table.concat(parts, " ", 3)

          -- Multi-chest keys support +/- prefix for add/remove
          if MULTI_CHEST_KEYS[path] and rawValue:sub(1, 1) == "+" then
            local name = rawValue:sub(2)
            local current = inventory.normalize(getConfigValue(path))
            -- Add if not already present
            local already = false
            for _, n in ipairs(current) do
              if n == name then already = true; break end
            end
            if not already then
              current[#current + 1] = name
            end
            local saveVal = #current == 1 and current[1] or current
            saveConfigOverride(path, saveVal)
            term.setTextColor(colors.lime)
            print("Added " .. name .. " to " .. path)
            term.setTextColor(colors.white)
            tracker.addLog("Config added: " .. path .. " += " .. name)

          elseif MULTI_CHEST_KEYS[path] and rawValue:sub(1, 1) == "-" then
            local name = rawValue:sub(2)
            local current = inventory.normalize(getConfigValue(path))
            local newList = {}
            for _, n in ipairs(current) do
              if n ~= name then newList[#newList + 1] = n end
            end
            local saveVal
            if #newList == 0 then saveVal = nil
            elseif #newList == 1 then saveVal = newList[1]
            else saveVal = newList
            end
            saveConfigOverride(path, saveVal)
            term.setTextColor(colors.lime)
            print("Removed " .. name .. " from " .. path)
            term.setTextColor(colors.white)
            tracker.addLog("Config removed: " .. path .. " -= " .. name)

          else
            local value = rawValue
            -- Auto-detect numeric values
            local numVal = tonumber(value)
            if numVal then value = numVal end
            saveConfigOverride(path, value)
            term.setTextColor(colors.lime)
            print("Set " .. path .. " = " .. tostring(value))
            term.setTextColor(colors.white)
            tracker.addLog("Config set: " .. path .. " = " .. tostring(value))
          end
        else
          print("Unknown key: " .. path)
          print("Run 'config' to see available keys.")
        end

      else
        -- Show a section or single key
        local filter = parts[2]
        local found = false
        for path, desc in pairs(CONFIGURABLE) do
          if path:find(filter, 1, true) then
            local val = getConfigValue(path)
            local display_val = formatConfigValue(path, val)
            local hasVal = val ~= nil and (type(val) ~= "table" or #val > 0)
            term.setTextColor(hasVal and colors.lime or colors.lightGray)
            print(string.format("  %-38s %s", path, display_val))
            term.setTextColor(colors.lightGray)
            print("    " .. desc)
            term.setTextColor(colors.white)
            found = true
          end
        end
        if not found then
          print("No config keys matching: " .. filter)
        end
      end

    elseif cmd == "update" then
      print("Updating BeeOS from GitHub...")
      local successCount, failCount = updater.update(print)
      print()
      if failCount == 0 then
        term.setTextColor(colors.lime)
        print(string.format("Updated %d files.", successCount))
        term.setTextColor(colors.white)
        print("Reboot to apply changes (run 'stop' then reboot).")
      else
        term.setTextColor(colors.orange)
        print(string.format("%d OK, %d failed.", successCount, failCount))
        term.setTextColor(colors.white)
      end
      tracker.addLog("Update: " .. successCount .. " OK, " .. failCount .. " failed")

    elseif cmd == "help" then
      print("Commands:")
      print("  status       - Show system status")
      print("  layers       - Describe what each layer does")
      print("  species      - List all species")
      print("  log          - Show recent activity")
      print("  enable <l>   - Enable a layer")
      print("  disable <l>  - Disable a layer")
      print("  target <sp>  - Prioritize a species")
      print("  config       - View/set configuration")
      print("  update       - Update BeeOS from GitHub")
      print("  rescan       - Rescan network")
      print("  stop         - Shut down BeeOS")

    elseif cmd and cmd ~= "" then
      print("Unknown command. Type 'help' for commands.")
    end
  end
end

--- Graceful shutdown: extract in-progress items from all machines.
local function shutdown()
  tracker.addLog("Shutdown: extracting machine contents")

  -- Apiaries: extract output (princesses, drones, products)
  for name, p in pairs(machines.apiary or {}) do
    pcall(apiary.extractOutput, name, p, config)
  end

  -- Samplers: collect completed samples, return spent drones
  pcall(sampler.collectOutput, machines, config)

  -- Imprinters: collect imprinted bees, waste
  local imprinters = {}
  if config.machines.imprinters then
    for _, name in ipairs(config.machines.imprinters) do
      imprinters[name] = peripheral.wrap(name)
    end
  else
    imprinters = machines.imprinter or {}
  end
  for impName, imp in pairs(imprinters) do
    if imp then
      pcall(imprinter.collectOutput, impName, imp, config)
    end
  end

  -- Analyzers: collect analyzed bees
  pcall(analyzer.tick, machines, config)

  -- Mutatrons: collect mutation results
  pcall(discovery.checkMutatron, machines, config)

  -- Transposers: extract samples, blanks, labware
  pcall(sampler.extractTransposers, machines, config)

  -- Turtle: collect crafted templates
  pcall(sampler.collectFromTurtle, config)

  tracker.addLog("Shutdown: extraction complete")
end

--- Main entry point
local function main()
  -- Load config overrides from persistent state
  loadConfigOverrides()

  -- Restore persisted layer states
  local savedLayers = state.load("layers")
  if savedLayers then
    for k, v in pairs(savedLayers) do
      if config.layers[k] ~= nil then
        config.layers[k] = v
      end
    end
  end

  -- Clear logs and log startup
  tracker.log = {}
  tracker.addLog("BeeOS starting up")

  -- Boot sequence
  term.setTextColor(colors.yellow)
  print("=== BeeOS Boot ===")
  term.setTextColor(colors.white)

  -- 1. Network scan
  write("  Network scan... ")
  rescanNetwork()
  term.setTextColor(colors.lime)
  print(network.count(machines, "chest") .. " chests, " ..
    network.count(machines, "apiary") .. " apiaries")
  term.setTextColor(colors.white)

  -- 2. Restore tracker state from disk
  write("  Restoring catalog... ")
  tracker.restore()
  local restored = tracker.stats()
  term.setTextColor(colors.lime)
  print(restored.discovered .. " species")
  term.setTextColor(colors.white)

  -- 3. Immediate inventory scan for fresh data
  write("  Inventory scan... ")
  local scanOk, invCount, itemCount = pcall(tracker.scan, machines)
  if scanOk then
    local stats = tracker.stats()
    term.setTextColor(colors.lime)
    print(stats.discovered .. " species, " ..
      (itemCount or 0) .. " items in " .. (invCount or 0) .. " inventories")
    tracker.addLog("Boot scan: " .. stats.discovered .. " species, " ..
      (itemCount or 0) .. " items")
  else
    term.setTextColor(colors.red)
    print("FAILED: " .. tostring(invCount))
  end
  term.setTextColor(colors.white)

  -- 4. Init display with fresh data
  write("  Display init... ")
  display.init(config)
  display.machines = machines
  if display.monitor then
    term.setTextColor(colors.lime)
    print(display.monitorName)
  else
    term.setTextColor(colors.lightGray)
    print("no monitor")
  end
  term.setTextColor(colors.white)

  print()

  -- Run all loops in parallel
  parallel.waitForAny(
    trackerLoop,
    apiaryLoop,
    machineCollectorLoop,
    samplerLoop,
    discoveryLoop,
    imprinterLoop,
    analyzerLoop,
    surplusLoop,
    traitExportLoop,
    displayLoop,
    touchLoop,
    terminalLoop
  )

  -- Graceful shutdown: extract items from machines
  shutdown()

  -- Save state (includes shutdown log entries)
  tracker.addLog("BeeOS shutdown")
  state.save("catalog", tracker.catalog)
  state.save("log", tracker.log)

  -- Clear terminal and monitor
  term.clear()
  term.setCursorPos(1, 1)
  if display.monitor then
    display.monitor.setBackgroundColor(colors.black)
    display.monitor.clear()
    display.monitor.setCursorPos(1, 1)
  end

  print("BeeOS stopped.")
end

main()
