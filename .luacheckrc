-- LuaCheck config for ComputerCraft/CC:Tweaked
std = "lua51"

-- CC:Tweaked globals
globals = {
  -- Core CC APIs
  "fs", "http", "os", "peripheral", "rednet", "redstone", "rs",
  "term", "textutils", "turtle", "pocket", "commands",
  "shell", "multishell", "settings", "colors", "colours",
  "keys", "paintutils", "parallel", "window", "vector",

  -- Global functions
  "sleep", "write", "print", "printError", "read",
  "tostring", "tonumber", "type", "error", "pcall", "xpcall",
  "pairs", "ipairs", "next", "select", "unpack",
  "setmetatable", "getmetatable", "rawget", "rawset",
  "string", "table", "math", "bit32", "coroutine",
}

-- Don't warn about unused loop variables starting with _
unused_args = false

-- Max line length (CC monitors are 51 chars wide but code can be longer)
max_line_length = 120
