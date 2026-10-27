-- Can a natural be hidden by setting kNoteAccidentalVisibility_v3 directly, to the value that
-- Edit.HideAccidental leaves? Runs on the recipe's scratch copy (chart flow first, treble voice holds C5 Ab5 G#5
-- G5 E6 G#6, the G5's natural hidden by the command). Adds an A5 after the Ab5, which would show a natural, and
-- sets the property on it directly. args.set = false leaves the new note alone (for a before/after capture).
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])")
local mine = here .. "?.lua;" .. here .. "lib/?.lua"
for name in pairs(package.loaded) do
  if package.searchpath(name, mine) then package.loaded[name] = nil end
end
if not package.path:find(mine, 1, true) then package.path = mine .. ";" .. package.path end
local probe = require("probe")

probe.run("26_naturals", function(p)
  local app = DoApp.DoApp()
  local ctx = DoCore.PropertyContext()
  local chart = app.currentScore.flows[1]
  local treble = chart.voiceStreams[1]
  local hidden, value
  for _, e in ipairs(treble.events) do
    local t = tostring(e)
    if t:find(" G5 ", 1, true) then
      hidden = e
      value = e.propertyTable:get("kNoteAccidentalVisibility_v3", ctx)
    end
  end
  if not p:check("found the G5 whose natural the command hid", hidden ~= nil) then return end
  p:fact("v3", tostring(value))
  local okType, vtype = pcall(function() return value.type end)
  p:fact("v3type", okType and tostring(vtype) or "?")
  local a5 = treble:createNote(DoCore.RhythmicLength(4), DoCore.RhythmicLength(1),
    DoCore.MIDIPitchWithSpelling.fromString("A5"))
  a5.propertyTable:set("kNoteHideStem", DoCore.Variant.createString("true"), ctx)
  if p.args.set ~= false then
    local okSet, setResult = pcall(function() return a5.propertyTable:set("kNoteAccidentalVisibility_v3", value, ctx) end)
    p:fact("setWithSameVariant", okSet and tostring(setResult) or tostring(setResult))
    local back = a5.propertyTable:get("kNoteAccidentalVisibility_v3", ctx)
    p:fact("readBack", tostring(back))
    p:check("the new note now holds the same value", tostring(back) == tostring(value))
  end
end)
