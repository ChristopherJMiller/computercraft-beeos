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
  { path = "lib/imprinter.lua", desc = "Trait imprinter" },
  { path = "lib/display.lua", desc = "Monitor display" },
  { path = "lib/updater.lua", desc = "Updater" },

  -- Turtle
  { path = "turtle/crafter.lua", desc = "Crafting turtle" },

  -- Tools
  { path = "tools/scan.lua", desc = "Network scanner" },
  { path = "tools/inspect.lua", desc = "Bee inspector" },
  { path = "tools/slots.lua", desc = "Slot mapper" },
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
-- @param printFn Optional function(msg) for output (defaults to print)
-- @return number successCount, number failCount
function updater.update(printFn)
  printFn = printFn or print

  local success = 0
  local failed = 0

  for _, file in ipairs(updater.FILES) do
    -- Skip config.lua during updates to preserve user defaults
    if file.path ~= "config.lua" then
      local url = updater.BASE_URL .. file.path
      printFn("  " .. file.path .. " ... ")

      local ok, err = updater.download(url, file.path)
      if ok then
        printFn("  " .. file.path .. " OK")
        success = success + 1
      else
        printFn("  " .. file.path .. " FAIL: " .. (err or "unknown"))
        failed = failed + 1
      end
    end
  end

  return success, failed
end

return updater
