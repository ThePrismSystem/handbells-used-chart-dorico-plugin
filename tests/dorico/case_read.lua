-- readscore.scan on a scratch copy: players, records, unread notes, the route taken, and that the music is the
-- same afterwards.
--   args.forcePaste: read through the pasted copy even where stream.events works
--   args.expect: optional {players = {...}, records = n, histogram = {["head|colour"] = n}, pastedFlows = n}
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])")
local repo = here .. "../../"
local mine = here .. "lib/?.lua;" .. repo .. "spike/lib/?.lua;" .. repo .. "plugin/Handbells Used Chart/?.lua"
for name in pairs(package.loaded) do
  if name:match("^hbuc") or package.searchpath(name, mine) then package.loaded[name] = nil end
end
if not package.path:find(mine, 1, true) then package.path = mine .. ";" .. package.path end
local probe = require("probe")

probe.run("case_read", function(p)
  -- required here, not above: a module that fails to load is then reported, and the copy closed
  local cases = require("cases")
  local readscore = require("hbuc.dorico.readscore")
  local ctx = cases.context(p)
  local app = ctx.app
  local before = readscore.summary(app.currentScore)
  local t0 = os.clock()
  local scan = readscore.scan(app, { log = ctx.log, forcePaste = p.args.forcePaste })
  p:fact("seconds", os.clock() - t0)
  local after = readscore.summary(app.currentScore)

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
  p:fact("unread", scan.unread)
  p:fact("pastedFlows", scan.pastedFlows)
  p:fact("histogram", histogram)
  p:fact("byInstrument", byInstrument)
  p:fact("summary", after)

  p:check("the music is as it was", after == before, after .. " vs " .. before)
  p:check("no note unread", scan.unread == 0, scan.unread)
  local want = p.args.expect or {}
  if want.players then p:check("players", table.concat(names, "|") == table.concat(want.players, "|"),
    table.concat(names, "|")) end
  if want.records then p:check("record count", #scan.records == want.records, #scan.records) end
  if want.pastedFlows then p:check("route", scan.pastedFlows == want.pastedFlows, scan.pastedFlows) end
  if want.histogram then
    local same = true
    for k, n in pairs(want.histogram) do if histogram[k] ~= n then same = false end end
    for k, n in pairs(histogram) do if want.histogram[k] ~= n then same = false end end
    p:check("noteheads and colours", same)
  end
end)
