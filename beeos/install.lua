-- BeeOS Installer
-- Downloads all BeeOS files from GitHub.
-- Usage: wget run https://raw.githubusercontent.com/ChristopherJMiller/computercraft-beeos/main/beeos/install.lua

-- Bootstrap: we need lib/updater.lua but it doesn't exist yet.
-- Download it first, then require it for the rest.
local REPO = "ChristopherJMiller/computercraft-beeos"
local FALLBACK_URL = "https://raw.githubusercontent.com/" .. REPO .. "/main/beeos/"

--- Resolve commit-pinned base URL to bypass GitHub CDN caching.
local function resolveBaseURL()
  local apiUrl = "https://api.github.com/repos/" .. REPO .. "/commits/main"
  local response = http.get(apiUrl, { ["Accept"] = "application/vnd.github.v3.sha" })
  if not response then return nil end
  local sha = response.readAll()
  response.close()
  if not sha or #sha ~= 40 then return nil end
  return "https://raw.githubusercontent.com/" .. REPO .. "/" .. sha .. "/beeos/"
end

local function bootstrapDownload(url, path)
  local response = http.get(url)
  if not response then return false end
  local content = response.readAll()
  response.close()
  if not content or #content == 0 then return false end
  local dir = fs.getDir(path)
  if dir and dir ~= "" and not fs.exists(dir) then
    fs.makeDir(dir)
  end
  local f = fs.open(path, "w")
  if not f then return false end
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

  if isTurtle then
    print("Detected: Crafting Turtle")
    print("Installing turtle crafter only...")
  else
    print("Detected: Computer")
    print("Installing full BeeOS...")
  end
  print()

  -- Create directories
  local dirs = { "lib", "turtle", "tools", "data", "data/presets" }
  for _, dir in ipairs(dirs) do
    if not fs.exists(dir) then
      fs.makeDir(dir)
    end
  end

  -- Resolve commit-pinned URL to avoid CDN caching
  local BASE_URL = resolveBaseURL() or FALLBACK_URL

  -- Bootstrap the updater module first
  term.setTextColor(colors.lightGray)
  write("  lib/updater.lua ")
  local ok = bootstrapDownload(BASE_URL .. "lib/updater.lua", "lib/updater.lua")
  if ok then
    term.setTextColor(colors.lime)
    print("OK")
  else
    term.setTextColor(colors.red)
    print("FAIL")
    print("Cannot download updater. Check internet connection.")
    term.setTextColor(colors.white)
    return
  end

  local updater = require("lib.updater")

  -- Pick file list
  local fileList = isTurtle and updater.TURTLE_FILES or updater.FILES

  -- Download files
  local success = 0
  local failed = 0

  for _, file in ipairs(fileList) do
    -- Skip updater (already downloaded) but download everything else including config.lua
    if file.path ~= "lib/updater.lua" then
      local url = BASE_URL .. file.path
      term.setTextColor(colors.lightGray)
      write("  " .. file.path .. " ")

      local isNew = not fs.exists(file.path)
      local dlOk, err = updater.download(url, file.path)
      if dlOk then
        term.setTextColor(colors.lime)
        print(isNew and "NEW" or "OK")
        success = success + 1
      else
        term.setTextColor(colors.red)
        print("FAIL: " .. (err or "unknown"))
        failed = failed + 1
      end
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
  print(string.format("Done: %d OK, %d failed", success + 1, failed))

  if failed == 0 then
    term.setTextColor(colors.lime)
    if isTurtle then
      print("Turtle crafter installed! Reboot to start.")
    else
      print("BeeOS installed! Run 'beeos' to start.")
      print()
      print("Quick start:")
      print("  1. Run 'tools/scan' to discover peripherals")
      print("  2. Run 'tools/inspect <chest> <slot>' to test bee reading")
      print("  3. Use 'config' command inside BeeOS to set chest names")
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
