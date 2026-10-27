-- Does stream:dump() have a more detailed form that shows note properties (notehead set, colour)? Lists
-- dump's overloads (a bound call with bad arguments returns them) and tries likely arguments, keeping the
-- part of each dump around a note known to have a diamond head and a colour. Read-only.
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])")
local mine = here .. "?.lua;" .. here .. "lib/?.lua"
for name in pairs(package.loaded) do
  if package.searchpath(name, mine) then package.loaded[name] = nil end
end
if not package.path:find(mine, 1, true) then package.path = mine .. ";" .. package.path end
local probe = require("probe")

probe.run("19_dump_detail", function(p)
  local app = DoApp.DoApp()
  local flow = app.currentScore.flows[1]
  local ctx = DoCore.PropertyContext()
  -- find a note with a notehead override and a colour through .events (the fixture has no lyrics or slurs)
  local target, stream
  for _, s in ipairs(flow.voiceStreams) do
    for _, e in ipairs(s.events) do
      local okH, h = pcall(function() return tostring(e.propertyTable:get("kNoteheadSetOverride", ctx)) end)
      local okC, c = pcall(function() return tostring(e.propertyTable:get("kEventColour", ctx)) end)
      if not target and okH and h ~= "" and okC and c ~= "" then target, stream = e, s end
    end
  end
  p:check("found a coloured note with a notehead", target ~= nil)
  p:fact("target", tostring(target))
  local plain = stream:dump()
  local at = plain:find("(id:" .. target.id .. ")", 1, true)
  p:fact("plainAround", at and plain:sub(math.max(1, at - 200), at + 300) or "not found")
  local tries = {
    { "no-args overloads", function() return stream.dump() end },
    { "true", function() return stream:dump(true) end },
    { "1", function() return stream:dump(1) end },
    { "2", function() return stream:dump(2) end },
    { "'verbose'", function() return stream:dump("verbose") end },
    { "ctx", function() return stream:dump(ctx) end },
  }
  local results = {}
  for _, t in ipairs(tries) do
    local ok, v = pcall(t[2])
    local text = tostring(v)
    local where = text:find("(id:" .. target.id .. ")", 1, true)
    results[#results + 1] = { try = t[1], ok = ok, length = #text,
      sameAsPlain = (text == plain), around = where and text:sub(math.max(1, where - 100), where + 400) or text:sub(1, 400) }
  end
  p:fact("tries", results)
  local okPT, ptText = pcall(tostring, target.propertyTable)
  p:fact("propertyTableTostring", okPT and ptText:sub(1, 800) or ("error " .. tostring(ptText)))
end)
