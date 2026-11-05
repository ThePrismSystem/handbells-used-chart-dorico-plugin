-- Does Project.Player.Rename with the id of a player that no longer exists crash Dorico? doc.playerIds tries ids in
-- turn from 0, and a project whose players were deleted has gaps (Goodbye Blue Sky: one player, id 0, and the next
-- id 3). Also: which id does score:addPlayer give a new player there? Scratch copy only.
-- args: {add = <players to add first>, ids = {<ids to rename, in order>}}. Each step is appended to
-- <run>/55-steps.txt before it runs, so a crash leaves the last step tried.
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])")
local repo = here .. "../"
local mine = here .. "?.lua;" .. here .. "lib/?.lua;" .. repo .. "plugin/Handbells Used Chart/?.lua"
for name in pairs(package.loaded) do
  if name:match("^hbuc") or package.searchpath(name, mine) then package.loaded[name] = nil end
end
if not package.path:find(mine, 1, true) then package.path = mine .. ";" .. package.path end
local probe = require("probe")

probe.run("55_missing_player_id", function(p)
  local constants = require("hbuc.constants")
  local doc = require("hbuc.dorico.doc")
  local app = DoApp.DoApp()
  local stepsPath = probe.runDir .. "55-steps.txt"
  os.remove(stepsPath)
  local function step(text)
    local f = assert(io.open(stepsPath, "ab"))
    f:write(text, "\n")
    f:close()
  end
  local function names()
    local out = {}
    for _, pl in ipairs(app.currentScore.players) do out[#out + 1] = doc.playerKey(pl) .. "=" .. tostring(pl) end
    return table.concat(out, "; ")
  end
  local function holder(token)
    for _, pl in ipairs(app.currentScore.players) do
      if tostring(pl) == token then return doc.playerKey(pl) end
    end
    return "none"
  end
  p:fact("before", names())
  step("before " .. names())

  for i = 1, p.args.add or 0 do
    step("addPlayer " .. i)
    local key = doc.playerKey(app.currentScore:addPlayer(constants.GRAND_INSTRUMENT, false, 1))
    step("added key " .. key)
  end
  p:fact("afterAdd", names())

  local held = {}
  for _, id in ipairs(p.args.ids or {}) do
    step("rename " .. id)
    app:doCommand("Project.Player.Rename?PlayerID=" .. id .. "&Name=HBUCP" .. id)
    held[#held + 1] = id .. "->" .. holder("HBUCP" .. id)
    step("renamed " .. held[#held])
  end
  p:fact("held", held)
  p:fact("after", names())
end)
