-- BeeOS - ComputerCraft Bee Automation System
-- Main orchestrator: runs all layers in parallel with error recovery.

local config = require("config")
local network = require("lib.network")
local tracker = require("lib.tracker")
local apiary = require("lib.apiary")
local sampler = require("lib.sampler")
local discovery = require("lib.discovery")
local surplus = require("lib.surplus")
local mutations = require("lib.mutations")
local display = require("lib.display")
local state = require("lib.state")

-- Runtime state
local running = true
local machines = {}

--- Rescan the network for machines.
local function rescanNetwork()
  machines = network.scan()
  tracker.addLog("Network scan: " ..
    network.count(machines, "apiary") .. " apiaries, " ..
    network.count(machines, "sampler") .. " samplers, " ..
    network.count(machines, "mutatron") .. " mutatrons")
end

--- Layer 0: Passive Tracker loop
local function trackerLoop()
  tracker.restore()
  while running do
    if config.layers.tracker then
      local ok, err = pcall(tracker.scan, machines)
      if not ok then
        tracker.addLog("Tracker error: " .. tostring(err))
      end
    end
    sleep(config.timing.trackerInterval)
  end
end

--- Layer 1: Apiary Manager loop
local function apiaryLoop()
  while running do
    if config.layers.apiary then
      for name, p in pairs(machines.apiary or {}) do
        local ok, err = pcall(apiary.check, name, p, config)
        if not ok then
          tracker.addLog("Apiary error (" .. name .. "): " .. tostring(err))
        end
      end
    end
    sleep(config.timing.apiaryInterval)
  end
end

--- Layer 2: Sample & Template Manager loop
local function samplerLoop()
  while running do
    if config.layers.sampler then
      local ok, err = pcall(sampler.processDrones, machines, config)
      if not ok then
        tracker.addLog("Sampler error: " .. tostring(err))
      end

      ok, err = pcall(sampler.collectOutput, machines, config)
      if not ok then
        tracker.addLog("Sample collection error: " .. tostring(err))
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

  while running do
    if config.layers.discovery then
      -- Load mutation graph on first enable
      if not loaded then
        local ok, err = mutations.load(config.machines.analyzer)
        if ok then
          loaded = true
          tracker.allSpecies = mutations.allSpecies
          discovery.init()
          tracker.addLog("Mutation graph loaded: " ..
            #mutations.allSpecies .. " species")
        else
          tracker.addLog("Cannot load mutations: " .. tostring(err))
        end
      end

      if loaded then
        -- Sync discovered set with tracker catalog
        for species in pairs(tracker.catalog) do
          discovery.markDiscovered(species)
        end

        local ok, err = pcall(discovery.tick, machines, config)
        if not ok then
          tracker.addLog("Discovery error: " .. tostring(err))
        end
      end
    end
    sleep(config.timing.discoveryInterval)
  end
end

--- Surplus management loop
local function surplusLoop()
  while running do
    if config.layers.sampler or config.layers.apiary then
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

--- Display refresh loop
local function displayLoop()
  display.init(config)

  while running do
    -- Sync layer states to display
    display.layerStates = {
      tracker = config.layers.tracker,
      apiary = config.layers.apiary,
      sampler = config.layers.sampler,
      discovery = config.layers.discovery,
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
          local status = config.layers[action.layer] and "ON" or "OFF"
          tracker.addLog("Layer " .. action.layer .. ": " .. status)
          state.save("layers", config.layers)
        end
        -- Tab changes are handled inside display.handleTouch
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
      print("Shutting down...")

    elseif cmd == "status" then
      print("Layers:")
      for layer, enabled in pairs(config.layers) do
        term.setTextColor(enabled and colors.lime or colors.red)
        print("  " .. layer .. ": " .. (enabled and "ON" or "OFF"))
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
        print("Available: tracker, apiary, sampler, discovery")
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

    elseif cmd == "log" then
      for i = 1, math.min(10, #tracker.log) do
        local entry = tracker.log[i]
        print("  " .. (entry.message or ""))
      end

    elseif cmd == "help" then
      print("Commands:")
      print("  status       - Show system status")
      print("  species      - List all species")
      print("  log          - Show recent activity")
      print("  enable <l>   - Enable a layer")
      print("  disable <l>  - Disable a layer")
      print("  target <sp>  - Prioritize a species")
      print("  rescan       - Rescan network")
      print("  stop         - Shut down BeeOS")

    elseif cmd and cmd ~= "" then
      print("Unknown command. Type 'help' for commands.")
    end
  end
end

--- Main entry point
local function main()
  -- Restore persisted layer states
  local savedLayers = state.load("layers")
  if savedLayers then
    for k, v in pairs(savedLayers) do
      if config.layers[k] ~= nil then
        config.layers[k] = v
      end
    end
  end

  -- Initial network scan
  rescanNetwork()
  network.printSummary(machines)
  print()

  -- Run all loops in parallel
  parallel.waitForAny(
    trackerLoop,
    apiaryLoop,
    samplerLoop,
    discoveryLoop,
    surplusLoop,
    displayLoop,
    touchLoop,
    terminalLoop
  )

  -- Cleanup
  tracker.addLog("BeeOS shutdown")
  state.save("catalog", tracker.catalog)
  state.save("log", tracker.log)
  print("BeeOS stopped.")
end

main()
