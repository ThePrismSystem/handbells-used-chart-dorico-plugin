-- What does Edit.Undo undo when a script sends it? Runs args.steps in order ("NEWFLOW" makes a flow with
-- Project.Flow.New; anything else is sent as a command) and reports every flow's title and the flow count. Scratch
-- copy only.
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])")
local repo = here .. "../"
local mine = here .. "?.lua;" .. here .. "lib/?.lua;" .. repo .. "plugin/Handbells Used Chart/?.lua"
for name in pairs(package.loaded) do
  if name:match("^hbuc") or package.searchpath(name, mine) then package.loaded[name] = nil end
end
if not package.path:find(mine, 1, true) then package.path = mine .. ";" .. package.path end
local probe = require("probe")

local function titles(app)
  local base = probe.runDir .. "undo-titles"
  os.remove(base .. ".csv")
  app:doCommand("File.Export.Text?File=" .. base .. ".txt&Show=false")
  local f = assert(io.open(base .. ".csv", "rb"))
  local csv = f:read("*a")
  f:close()
  local out = {}
  for n, t in pairs(require("hbuc.textexport").flowTitles(csv)) do
    if type(n) == "number" then out[#out + 1] = n .. "=" .. t end
  end
  table.sort(out)
  return table.concat(out, "; ")
end

probe.run("29_undo_inside", function(p)
  local app = DoApp.DoApp()
  p:fact("before", titles(app) .. " | flows " .. #app.currentScore.flows)
  local log = {}
  for _, step in ipairs(p.args.steps or {}) do
    if step == "NEWFLOW" then app:doCommand("Project.Flow.New") else app:doCommand(step) end
    log[#log + 1] = step .. " -> flows " .. #app.currentScore.flows
  end
  p:fact("steps", log)
  p:fact("after", titles(app) .. " | flows " .. #app.currentScore.flows)
end)
