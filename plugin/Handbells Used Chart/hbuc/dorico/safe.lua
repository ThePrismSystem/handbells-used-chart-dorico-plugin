-- The run log, and a protected call that logs a traceback. The log is rewritten on every run and each line is
-- written straight away, so a run that Dorico ends early still leaves its log behind.
local safe = {}

local Log = {}
Log.__index = Log

function Log:line(...)
  local parts = {}
  for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
  local f = io.open(self.path, "ab")
  if f then
    f:write(os.date("%H:%M:%S "), table.concat(parts, " "), "\n")
    f:close()
  end
end

function safe.logger(path)
  local f = io.open(path, "wb")
  if f then f:close() end
  return setmetatable({ path = path }, Log)
end

-- An error's first line, without the file and line Lua puts in front of a string error.
local function firstLine(err)
  if type(err) == "table" then return err end
  local text = tostring(err):match("^[^\n]*") or ""
  return (text:gsub("^[^:]*%.lua:%d+: ", ""))
end
safe.firstLine = firstLine

-- true, result... on success; false, message (or the error table itself) on failure, with the traceback logged.
function safe.call(log, what, fn, ...)
  local args = { n = select("#", ...), ... }
  local trace
  local results = { xpcall(function() return fn(unpack(args, 1, args.n)) end, function(err)
    trace = debug.traceback(type(err) == "table" and ("error table: " .. tostring(err.code or err.message)) or tostring(err), 2)
    return err
  end) }
  if results[1] then return unpack(results) end
  log:line("FAILED", what, trace)
  return false, firstLine(results[2])
end

return safe
