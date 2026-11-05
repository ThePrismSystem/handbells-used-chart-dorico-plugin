-- Draws a chart of made-up sections at the size chartlayout.staffPercent gives, for spike/56_chart_width.py to
-- capture. Scratch copy only.
-- args: {sections = {<column counts, in order>}, kind = "plain" (naturals) or "accidentals" (a different sharp or flat
-- in every column, on both staves), crotchet = <a value for the full score's noteSpacingOptions.crotchetSize>}.
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])")
local repo = here .. "../"
local mine = here .. "?.lua;" .. here .. "lib/?.lua;" .. repo .. "tests/dorico/lib/?.lua;" .. repo
  .. "plugin/Handbells Used Chart/?.lua"
for name in pairs(package.loaded) do
  if name:match("^hbuc") or package.searchpath(name, mine) then package.loaded[name] = nil end
end
if not package.path:find(mine, 1, true) then package.path = mine .. ";" .. package.path end
local probe = require("probe")

-- Every spelling once: a bar doesn't repeat an accidental, so a repeated one would widen only its first column.
local function spellings(kind, octaves)
  local out = {}
  for _, sign in ipairs(kind == "plain" and { "" } or { "#", "b" }) do
    for _, octave in ipairs(octaves) do
      for letter in ("CDEFGAB"):gmatch(".") do out[#out + 1] = letter .. sign .. octave end
    end
  end
  return out
end

probe.run("56_chart_width", function(p)
  local cases = require("cases")
  local chartlayout = require("hbuc.chartlayout")
  local commands = require("hbuc.commands")
  local doc = require("hbuc.dorico.doc")
  local savedcopy = require("hbuc.dorico.savedcopy")
  local writechart = require("hbuc.dorico.writechart")
  local ctx = cases.context(p)
  local app, log = ctx.app, ctx.log
  if p.args.crotchet then
    app:doCommand(commands.layoutOptions(app.currentScore.openScoreID, app.currentLayoutID,
      { ["noteSpacingOptions.crotchetSize"] = p.args.crotchet }))
  end
  local page = savedcopy.read(app, log, ctx.folders.temp).pages[app.currentLayoutID]
  p:fact("page", page)

  local treble, bass = spellings(p.args.kind, { 4, 5, 6 }), spellings(p.args.kind, { 2, 3, 4 })
  local sections, start = {}, 0
  for i, n in ipairs(p.args.sections) do
    local t, b = {}, {}
    for c = 1, n do
      t[c] = { treble[(c - 1) % #treble + 1] }
      b[c] = { bass[(c - 1) % #bass + 1] }
    end
    local step = i == #p.args.sections and chartlayout.LAST_STEP or 1
    sections[i] = { kind = "bells", slot = 1, label = "Width " .. n, start = start, step = step, columns = n,
      colour = "", treble = t, bass = b }
    start = start + n * step
  end
  local built = { warnings = {}, sections = sections }
  local percent = chartlayout.staffPercent(built, page)
  p:fact("staffPercent", percent)
  local musicKeys = {}
  for _, pl in ipairs(app.currentScore.players) do musicKeys[#musicKeys + 1] = doc.playerKey(pl) end
  writechart.write(app, built, { log = log, tempDir = ctx.folders.temp, slots = { { role = "grand", owner = "A" } },
    musicKeys = musicKeys, newPage = true, staffPercent = percent })
  p:check("drawn", true)
end)
