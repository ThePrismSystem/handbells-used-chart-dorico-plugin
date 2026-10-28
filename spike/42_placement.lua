-- Where does each flow land? Read-only, on the active project: its flows and layouts, and per page of the text
-- export, which flows have rows there and the frame and flow-info rows.
--   python tools/dorico/run_lua.py spike/42_placement.lua --on-active
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])")
local repo = here .. "../"
local mine = here .. "lib/?.lua;" .. repo .. "tests/dorico/lib/?.lua;" .. repo .. "plugin/Handbells Used Chart/?.lua"
for name in pairs(package.loaded) do
  if name:match("^hbuc") or package.searchpath(name, mine) then package.loaded[name] = nil end
end
if not package.path:find(mine, 1, true) then package.path = mine .. ";" .. package.path end
local probe = require("probe")

probe.run("42_placement", function(p)
  local textexport = require("hbuc.textexport")
  local files = require("hbuc.dorico.files")
  local app = DoApp.DoApp()
  local score = app.currentScore

  local flows = {}
  for i, f in ipairs(score.flows) do
    local names = {}
    for _, pl in ipairs(f.players) do names[#names + 1] = tostring(pl) end
    flows[#flows + 1] = i .. ": id " .. f.id .. ", " .. #f.voiceStreams .. " streams, players: " .. table.concat(names, "; ")
  end
  local players = {}
  for _, pl in ipairs(score.players) do players[#players + 1] = tostring(pl) end
  p:fact("players", players)
  p:fact("flows", flows)
  local layouts = {}
  for _, l in ipairs(score.layouts) do layouts[#layouts + 1] = l.id .. ": " .. tostring(l) .. ", " .. #l.players .. " players" end
  p:fact("layouts", layouts)

  local base = probe.runDir .. "placement"
  os.remove(base .. ".csv")
  app:doCommand("File.Export.Text?File=" .. base .. ".txt&Show=false")
  local csv = files.read(base .. ".csv")
  if not csv then error("File.Export.Text wrote no " .. base .. ".csv") end
  local rows = textexport.csvRows(csv)
  p:fact("header", rows[1])
  local pages, notable = {}, {}
  for _, rec in ipairs(textexport.csvRecords(csv)) do
    local where = "page " .. (rec.Page ~= "" and rec.Page or "-")
    local flow = (rec.FlowNumber or "") .. ":" .. (rec.FlowName or "")
    pages[where] = pages[where] or {}
    pages[where][flow] = (pages[where][flow] or 0) + 1
    if not rec.Type:match("^Lyric") and (rec.Type:match("Frame") or rec.Type:match("Flow Info") or rec.Text:match("HBUC")
        or rec.Text:match("Handbells Used")) then
      notable[#notable + 1] = table.concat({ where, flow, rec.Type, rec.ID, rec.Text:sub(1, 60) }, " | ")
    end
  end
  local summary = {}
  for where, byFlow in pairs(pages) do
    local parts = {}
    for flow, n in pairs(byFlow) do parts[#parts + 1] = "flow " .. flow .. " x" .. n end
    table.sort(parts)
    summary[#summary + 1] = where .. ": " .. table.concat(parts, "; ")
  end
  table.sort(summary)
  p:fact("pages", summary)
  p:fact("notable", notable)
end)
