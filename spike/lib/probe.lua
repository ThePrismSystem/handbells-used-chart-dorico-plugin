-- Probe harness for scripts run inside Dorico by tools/dorico/run_lua.py.
-- Reads the run's args (the file the runner's launcher names in HBUC_RUN, else <run>/args.json), runs the body under
-- xpcall, and writes <run>/result.json in one go:
--   {runId, name, ok, checks=[{label, ok, detail}], facts={...}, log=[...], error?}
local json = require("json")

local probe = {}

probe.runDir = require("rundir")()

local function readFile(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

local function writeFile(path, s)
  local tmp = path .. ".tmp"
  local f = assert(io.open(tmp, "wb"))
  f:write(s)
  f:close()
  os.remove(path)
  assert(os.rename(tmp, path))
end

local P = {}
P.__index = P

function P:check(label, cond, detail)
  local ok = cond and true or false
  self.checks[#self.checks + 1] = { label = label, ok = ok, detail = detail ~= nil and tostring(detail) or nil }
  if not ok then self.ok = false end
  return ok
end

function P:fact(key, value)
  self.facts[key] = value
end

function P:log(...)
  local t = {}
  for i = 1, select("#", ...) do t[#t + 1] = tostring(select(i, ...)) end
  self.lines[#self.lines + 1] = table.concat(t, "\t")
end

local function normalise(path)
  return (path or ""):gsub("\\", "/"):lower()
end

-- expected: args.expectScratch from the runner ({path = "<scratch .dorico>"} or {path = ""} for an import).
function probe.isExpectedScratch(expected, actualPath)
  return normalise(expected.path) == normalise(actualPath)
end

-- The active project's file path from the text export's first data row; "" if it was never saved.
-- (No Lua property exposes the path.)
function probe.projectPath(app)
  local base = probe.runDir .. "project-path"
  os.remove(base .. ".csv")
  app:doCommand("File.Export.Text?File=" .. base .. ".txt&Show=false")
  local f = io.open(base .. ".csv", "rb")
  if not f then error("File.Export.Text wrote no " .. base .. ".csv") end
  f:read("*l") -- header
  local row = f:read("*l") or ""
  f:close()
  return row:match('^"([^"]*)"') or ""
end

function probe.readArgs()
  local run = rawget(_G, "HBUC_RUN")
  local s = readFile(type(run) == "table" and run.args or (probe.runDir .. "args.json"))
  if not s then return {} end
  local ok, args = pcall(json.decode, s)
  return ok and args or {}
end

-- debug.traceback hands a non-string error back untouched, which would lose where it came from.
local function traceback(err)
  if type(err) ~= "string" then
    local ok, text = pcall(json.encode, err)
    err = "error object: " .. (ok and text or tostring(err))
  end
  return debug.traceback(err, 2)
end

function probe.run(name, body)
  local p = setmetatable({ args = probe.readArgs(), checks = {}, facts = {}, lines = {}, ok = true }, P)
  local ok, err = xpcall(function()
    local expected = p.args.expectScratch
    if expected then
      -- the runner opened a scratch copy: refuse to touch anything unless it is the active project
      local actual = probe.projectPath(DoApp.DoApp())
      p.facts.activeProjectPath = actual
      if not probe.isExpectedScratch(expected, actual) then
        p.facts.scratchVerified = false
        error("refusing to run: the active project is '" .. actual .. "', not the scratch copy '" .. expected.path .. "'")
      end
      p.facts.scratchVerified = true
      -- the runner closes exactly this project afterwards
      p.facts.scratchScoreID = DoApp.DoApp().currentScore.openScoreID
    end
    body(p)
  end, traceback)
  local result = {
    runId = p.args.runId or json.null,
    name = name,
    ok = ok and p.ok,
    checks = p.checks,
    facts = p.facts,
    log = p.lines,
  }
  if not ok then result.error = tostring(err) end
  local encoded
  local encOk, encErr = pcall(function() encoded = json.encode(result) end)
  if not encOk then
    encoded = json.encode({ runId = result.runId, name = name, ok = false,
      error = "could not encode result: " .. tostring(encErr), checks = {}, facts = {}, log = p.lines })
  end
  writeFile(probe.runDir .. "result.json", encoded)
  return result
end

return probe
