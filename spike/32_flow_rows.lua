-- How does the text export number flows, and does it list the hidden marker text? Lists the Flow Info rows
-- and any row whose text starts with HBUC|, next to score.flows' ids in order. Read-only.
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])")
local repo = here .. "../"
local mine = here .. "?.lua;" .. here .. "lib/?.lua;" .. repo .. "plugin/Handbells Used Chart/?.lua"
for name in pairs(package.loaded) do
  if name:match("^hbuc") or package.searchpath(name, mine) then package.loaded[name] = nil end
end
if not package.path:find(mine, 1, true) then package.path = mine .. ";" .. package.path end
local probe = require("probe")

probe.run("32_flow_rows", function(p)
  local textexport = require("hbuc.textexport")
  local app = DoApp.DoApp()
  local base = probe.runDir .. "flow-rows"
  os.remove(base .. ".csv")
  app:doCommand("File.Export.Text?File=" .. base .. ".txt&Show=false")
  local f = assert(io.open(base .. ".csv", "rb"))
  local csv = f:read("*a")
  f:close()
  local rows = {}
  for _, rec in ipairs(textexport.csvRecords(csv)) do
    if rec.Type:find("Flow Info", 1, true) or rec.Text:sub(1, 5) == "HBUC|" then
      rows[#rows + 1] = "[" .. rec.FlowNumber .. "] " .. rec.FlowName .. " | " .. rec.Type .. " | " .. rec.Text:sub(1, 40)
        .. " | id " .. rec.ID .. " | hidden " .. rec.Hidden
    end
  end
  p:fact("rows", rows)
  local ids = {}
  for i, fl in ipairs(app.currentScore.flows) do ids[#ids + 1] = i .. ":" .. fl.id end
  p:fact("flowIds", table.concat(ids, " "))
end)
