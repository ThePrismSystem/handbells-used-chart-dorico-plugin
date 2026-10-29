-- readscore.scan on a scratch copy: players, records, how long it took, and that the music and its flows are the
-- same afterwards.
--   args.expect: optional {players = {...}, records = n, histogram = {["head|colour"] = n}}
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])")
local repo = here .. "../../"
local mine = here .. "lib/?.lua;" .. repo .. "spike/lib/?.lua;" .. repo .. "plugin/Handbells Used Chart/?.lua"
for name in pairs(package.loaded) do
  if name:match("^hbuc") or package.searchpath(name, mine) then package.loaded[name] = nil end
end
-- first, whatever came before: the plug-in's entry file (test_run.py's RealDialog) leaves its install on the
-- path, and an older install there would be loaded instead
if package.path:sub(1, #mine + 1) ~= mine .. ";" then package.path = mine .. ";" .. package.path end
local probe = require("probe")

probe.run("case_read", function(p)
  -- required here, not above: a module that fails to load is then reported, and the copy closed
  local cases = require("cases")
  local readscore = require("hbuc.dorico.readscore")
  local ctx = cases.context(p)
  local app = ctx.app
  local before, flowsBefore = cases.summary(app.currentScore), #app.currentScore.flows
  local t0 = os.clock()
  local scan = readscore.scan(app, { log = ctx.log, layoutId = app.currentLayoutID, tempDir = ctx.folders.temp })
  p:fact("seconds", os.clock() - t0)
  p:fact("layoutId", app.currentLayoutID)
  local after = cases.summary(app.currentScore)

  local names, histogram, byInstrument, pitched = {}, {}, {}, 0
  for _, pl in ipairs(scan.players) do names[#names + 1] = pl.name end
  for _, r in ipairs(scan.records) do
    if r.pitch then
      pitched = pitched + 1
      local k = r.head .. "|" .. r.colour
      histogram[k] = (histogram[k] or 0) + 1
      k = table.concat({ r.instrument, r.pitch, r.head, r.colour }, "|")
      byInstrument[k] = (byInstrument[k] or 0) + 1
    end
  end
  p:fact("players", names)
  p:fact("records", #scan.records)
  p:fact("pitched", pitched)
  p:fact("histogram", histogram)
  p:fact("byInstrument", byInstrument)
  p:fact("summary", after)

  p:check("the music is as it was", after == before, after .. " vs " .. before)
  p:check("no flow added or taken away", #app.currentScore.flows == flowsBefore, #app.currentScore.flows)
  local want = p.args.expect or {}
  if want.players then p:check("players", table.concat(names, "|") == table.concat(want.players, "|"),
    table.concat(names, "|")) end
  if want.records then p:check("record count", #scan.records == want.records, #scan.records) end
  if want.histogram then
    local same = true
    for k, n in pairs(want.histogram) do if histogram[k] ~= n then same = false end end
    for k, n in pairs(histogram) do if want.histogram[k] ~= n then same = false end end
    p:check("noteheads and colours", same)
  end
end)
