-- BeeOS Updater
-- Shared download logic and file manifest for install and update.

local updater = {}

updater.BASE_URL = "https://raw.githubusercontent.com/ChristopherJMiller/computercraft-beeos/main/beeos/"

-- File manifest: all BeeOS files (path relative to beeos root)
updater.FILES = {
  -- Core
  { path = "beeos.lua", desc = "Main orchestrator" },
  { path = "startup.lua", desc = "Auto-start" },
  { path = "config.lua", desc = "Configuration" },

  -- Libraries
  { path = "lib/bee.lua", desc = "Bee genetics" },
  { path = "lib/network.lua", desc = "Network manager" },
  { path = "lib/inventory.lua", desc = "Inventory helpers" },
  { path = "lib/state.lua", desc = "Persistent state" },
  { path = "lib/tracker.lua", desc = "Layer 0: Tracker" },
  { path = "lib/apiary.lua", desc = "Layer 1: Apiaries" },
  { path = "lib/sampler.lua", desc = "Layer 2: Sampling" },
  { path = "lib/discovery.lua", desc = "Layer 3: Discovery" },
  { path = "lib/mutations.lua", desc = "Mutation graph" },
  { path = "lib/surplus.lua", desc = "Surplus manager" },
  { path = "lib/trait_export.lua", desc = "Trait exporter" },
  { path = "lib/imprinter.lua", desc = "Trait imprinter" },
  { path = "lib/analyzer.lua", desc = "Bee analyzer" },
  { path = "lib/display.lua", desc = "Monitor display" },
  { path = "lib/updater.lua", desc = "Updater" },

  -- Turtle
  { path = "turtle/crafter.lua", desc = "Crafting turtle" },

  -- Data
  { path = "data/presets/meatballcraft.lua", desc = "Meatballcraft mutations" },

  -- Tools
  { path = "tools/scan.lua", desc = "Network scanner" },
  { path = "tools/inspect.lua", desc = "Bee inspector" },
  { path = "tools/slots.lua", desc = "Slot mapper" },
  { path = "tools/mutations_debug.lua", desc = "Mutation debugger" },
}

-- Turtle-only files
updater.TURTLE_FILES = {
  { path = "turtle/crafter.lua", desc = "Crafting turtle" },
}

--- Download a single file from a URL.
-- @param url Source URL
-- @param path Local file path
-- @return boolean success, string|nil error
function updater.download(url, path)
  local response = http.get(url)
  if not response then
    return false, "HTTP request failed"
  end

  local content = response.readAll()
  response.close()

  if not content or #content == 0 then
    return false, "Empty response"
  end

  -- Ensure parent directory exists
  local dir = fs.getDir(path)
  if dir and dir ~= "" and not fs.exists(dir) then
    fs.makeDir(dir)
  end

  local f = fs.open(path, "w")
  if not f then
    return false, "Cannot write file"
  end
  f.write(content)
  f.close()
  return true
end

--- Update BeeOS by downloading all files except config.lua.
-- Fetches the latest file manifest from GitHub first so newly added
-- files are picked up without needing a reboot.
-- @param printFn Optional function(msg) for output (defaults to print)
-- @return number successCount, number failCount
function updater.update(printFn)
  printFn = printFn or print

  -- Fetch latest updater source to get current file manifest
  local response = http.get(updater.BASE_URL .. "lib/updater.lua")
  if not response then
    printFn("  Cannot reach GitHub")
    return 0, 1
  end
  local source = response.readAll()
  response.close()

  -- Save updated updater to disk
  local f = fs.open("lib/updater.lua", "w")
  if f then f.write(source); f.close() end

  -- Extract file paths from fresh source
  local files = {}
  for path in source:gmatch('path = "([^"]+)"') do
    files[#files + 1] = path
  end

  -- Download all files except config.lua and updater (already saved above)
  local success = 1  -- count updater as success
  local failed = 0

  for _, path in ipairs(files) do
    if path ~= "config.lua" and path ~= "lib/updater.lua" then
      local url = updater.BASE_URL .. path
      printFn("  " .. path .. " ... ")

      local isNew = not fs.exists(path)
      local ok, err = updater.download(url, path)
      if ok then
        printFn("  " .. path .. (isNew and " NEW" or " OK"))
        success = success + 1
      else
        printFn("  " .. path .. " FAIL: " .. (err or "unknown"))
        failed = failed + 1
      end
    end
  end

  return success, failed
end

return updater
