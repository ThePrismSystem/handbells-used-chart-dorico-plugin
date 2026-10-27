-- What happens to players' names through doc.playerIds (rename each id to a token, then back with Name only)?
-- Records every player's tostring before, after each step, and the ids found. Scratch copy only.
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])")
local repo = here .. "../"
local mine = here .. "?.lua;" .. here .. "lib/?.lua;" .. repo .. "plugin/Handbells Used Chart/?.lua"
for name in pairs(package.loaded) do
  if name:match("^hbuc") or package.searchpath(name, mine) then package.loaded[name] = nil end
end
if not package.path:find(mine, 1, true) then package.path = mine .. ";" .. package.path end
local probe = require("probe")

probe.run("31_player_names", function(p)
  local doc = require("hbuc.dorico.doc")
  local app = DoApp.DoApp()
  local log = { line = function() end }
  local function names()
    local out = {}
    for _, pl in ipairs(app.currentScore.players) do out[#out + 1] = doc.playerKey(pl) .. "=" .. tostring(pl) end
    return table.concat(out, "; ")
  end
  p:fact("before", names())
  local ids = doc.playerIds(app, log)
  local list = {}
  for k, id in pairs(ids) do list[#list + 1] = k .. "->" .. id end
  table.sort(list)
  p:fact("ids", table.concat(list, ", "))
  p:fact("afterIds", names())
  local later = {}
  for _ = 1, 3 do
    app:doCommand("Edit.SelectNone")
    later[#later + 1] = names()
  end
  p:fact("laterReads", later)
end)
