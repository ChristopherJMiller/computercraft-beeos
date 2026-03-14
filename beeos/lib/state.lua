-- BeeOS State Manager
-- Persistent state that survives reboots via filesystem serialization.

local state = {}
local STATE_DIR = "data"

-- Ensure data directory exists
if not fs.exists(STATE_DIR) then
  fs.makeDir(STATE_DIR)
end

--- Save a value to persistent storage.
-- @param key Storage key (becomes filename)
-- @param data Any serializable Lua value
function state.save(key, data)
  local path = STATE_DIR .. "/" .. key .. ".dat"
  local f = fs.open(path, "w")
  if not f then
    printError("Failed to save state: " .. path)
    return false
  end
  f.write(textutils.serialise(data))
  f.close()
  return true
end

--- Load a value from persistent storage.
-- @param key Storage key
-- @param default Default value if key doesn't exist
-- @return Stored value, or default
function state.load(key, default)
  local path = STATE_DIR .. "/" .. key .. ".dat"
  if not fs.exists(path) then
    return default
  end

  local f = fs.open(path, "r")
  if not f then
    return default
  end

  local content = f.readAll()
  f.close()

  local ok, data = pcall(textutils.unserialise, content)
  if ok and data ~= nil then
    return data
  else
    printError("Corrupt state file: " .. path)
    return default
  end
end

--- Delete a stored value.
-- @param key Storage key
function state.delete(key)
  local path = STATE_DIR .. "/" .. key .. ".dat"
  if fs.exists(path) then
    fs.delete(path)
  end
end

--- Check if a key exists in storage.
-- @param key Storage key
-- @return boolean
function state.exists(key)
  return fs.exists(STATE_DIR .. "/" .. key .. ".dat")
end

--- List all stored keys.
-- @return List of key strings
function state.keys()
  local result = {}
  if fs.exists(STATE_DIR) then
    for _, name in ipairs(fs.list(STATE_DIR)) do
      if name:sub(-4) == ".dat" then
        result[#result + 1] = name:sub(1, -5)
      end
    end
  end
  return result
end

return state
