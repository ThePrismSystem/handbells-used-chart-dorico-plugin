-- Stock-Lua test runner for the plug-in's pure modules.
--   lua52 tests/run.lua [filter]
-- Loads every tests/test_*.lua (or those whose name contains filter). Each returns
-- { testName = function(t) ... end }. Exits 1 on any failure.
local here = (arg and arg[0] or ""):match("^(.*[/\\])") or "./"
local root = here .. "../"
package.path = root .. "plugin/Handbells Used Chart/?.lua;" .. here .. "?.lua;" .. package.path

local filter = arg and arg[1]

local function listTests()
  local files = {}
  local cmd = package.config:sub(1, 1) == "\\" and ('dir /b "' .. here:gsub("/", "\\") .. 'test_*.lua" 2>nul')
    or ('ls "' .. here .. '" 2>/dev/null')
  local p = io.popen(cmd)
  for name in p:lines() do
    if name:match("^test_.*%.lua$") and (not filter or name:find(filter, 1, true)) then files[#files + 1] = name end
  end
  p:close()
  table.sort(files)
  return files
end

local T = {}
T.__index = T
-- Tests call these as t:eq and so on, though none of them needs t itself.
-- luacheck: push no self
function T:eq(got, want, label)
  if got ~= want then
    error((label or "values differ") .. ": got " .. tostring(got) .. ", want " .. tostring(want), 2)
  end
end
function T:ok(cond, label)
  if not cond then error((label or "condition false"), 2) end
end
function T:fails(fn, label)
  local ok = pcall(fn)
  if ok then error((label or "expected an error") .. ": no error was raised", 2) end
end
-- luacheck: pop

local passed, failed = 0, 0
for _, file in ipairs(listTests()) do
  local chunk, err = loadfile(here .. file)
  if not chunk then
    print("FAIL " .. file .. ": " .. err)
    failed = failed + 1
  else
    local okLoad, tests = pcall(chunk)
    if not okLoad or type(tests) ~= "table" then
      print("FAIL " .. file .. ": " .. tostring(tests))
      failed = failed + 1
    else
      local names = {}
      for name in pairs(tests) do names[#names + 1] = name end
      table.sort(names)
      for _, name in ipairs(names) do
        local ok, msg = pcall(tests[name], setmetatable({}, T))
        if ok then
          passed = passed + 1
        else
          failed = failed + 1
          print("FAIL " .. file:gsub("%.lua$", "") .. "." .. name .. ": " .. tostring(msg))
        end
      end
    end
  end
end
print(passed .. " passed, " .. failed .. " failed")
-- Running nothing is a failure too: a typo in the filter, or a file listing that came back empty.
if passed + failed == 0 then
  print("FAIL no tests ran")
  os.exit(1)
end
if failed > 0 then os.exit(1) end
