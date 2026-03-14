-- BeeOS Installer
-- Downloads all BeeOS files from GitHub Pages.
-- Usage: wget run https://<user>.github.io/computercraft-beeos/install.lua
-- Or: pastebin run <code>

local BASE_URL = "https://raw.githubusercontent.com/ChristopherJMiller/computercraft-beeos/main/beeos/"

-- File manifest: all files to download
local FILES = {
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
  { path = "lib/display.lua", desc = "Monitor display" },

  -- Turtle
  { path = "turtle/crafter.lua", desc = "Crafting turtle" },

  -- Tools
  { path = "tools/scan.lua", desc = "Network scanner" },
  { path = "tools/inspect.lua", desc = "Bee inspector" },
  { path = "tools/slots.lua", desc = "Slot mapper" },
}

-- Turtle-only files
local TURTLE_FILES = {
  { path = "turtle/crafter.lua", desc = "Crafting turtle" },
}

local function download(url, path)
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

local function main()
  term.setTextColor(colors.yellow)
  print("=== BeeOS Installer ===")
  term.setTextColor(colors.white)
  print()

  -- Detect if we're on a turtle
  local isTurtle = turtle ~= nil
  local fileList = isTurtle and TURTLE_FILES or FILES

  if isTurtle then
    print("Detected: Crafting Turtle")
    print("Installing turtle crafter only...")
  else
    print("Detected: Computer")
    print("Installing full BeeOS...")
  end
  print()

  -- Create directories
  local dirs = { "lib", "turtle", "tools", "data" }
  for _, dir in ipairs(dirs) do
    if not fs.exists(dir) then
      fs.makeDir(dir)
    end
  end

  -- Download files
  local success = 0
  local failed = 0

  for _, file in ipairs(fileList) do
    local url = BASE_URL .. file.path
    term.setTextColor(colors.lightGray)
    write("  " .. file.path .. " ")

    local ok, err = download(url, file.path)
    if ok then
      term.setTextColor(colors.lime)
      print("OK")
      success = success + 1
    else
      term.setTextColor(colors.red)
      print("FAIL: " .. (err or "unknown"))
      failed = failed + 1
    end
  end

  -- For turtle, set up startup
  if isTurtle then
    local f = fs.open("startup.lua", "w")
    f.write('shell.run("turtle/crafter")')
    f.close()
  end

  print()
  term.setTextColor(colors.yellow)
  print(string.format("Done: %d OK, %d failed", success, failed))

  if failed == 0 then
    term.setTextColor(colors.lime)
    if isTurtle then
      print("Turtle crafter installed! Reboot to start.")
    else
      print("BeeOS installed! Edit config.lua, then run 'beeos'")
      print()
      print("Quick start:")
      print("  1. Run 'tools/scan' to discover peripherals")
      print("  2. Run 'tools/inspect <chest> <slot>' to test bee reading")
      print("  3. Edit config.lua with your chest names")
      print("  4. Run 'beeos' to start")
    end
  else
    term.setTextColor(colors.orange)
    print("Some files failed. Check your internet connection.")
    print("You can re-run this installer to retry.")
  end

  term.setTextColor(colors.white)
end

main()
