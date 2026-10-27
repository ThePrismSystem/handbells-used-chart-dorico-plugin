-- Layer 1 must not touch Dorico: everything here runs, and is tested, outside it.
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./"
local dir = here .. "../plugin/Handbells Used Chart/hbuc/"

local function luaFiles()
  local files = {}
  local cmd = package.config:sub(1, 1) == "\\" and ('dir /b "' .. dir:gsub("/", "\\") .. '*.lua" 2>nul')
    or ('ls "' .. dir .. '" 2>/dev/null')
  local p = io.popen(cmd)
  for name in p:lines() do
    if name:match("%.lua$") then files[#files + 1] = name end
  end
  p:close()
  return files
end

return {
  hbuc_modules_exist = function(t)
    t:ok(#luaFiles() > 0, "no modules found in " .. dir)
  end,
  no_module_calls_dorico = function(t)
    for _, name in ipairs(luaFiles()) do
      local f = assert(io.open(dir .. name, "rb"))
      local src = f:read("*a")
      f:close()
      t:ok(not src:find("DoApp", 1, true) and not src:find("DoCore", 1, true), name .. " refers to DoApp/DoCore")
    end
  end,
}
