-- Write chart notes with exact spellings, hide stems and naturals, add a label and a hidden marker.
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])")
local mine = here .. "?.lua;" .. here .. "lib/?.lua;" .. here .. "../spike/lib/?.lua"
for name in pairs(package.loaded) do -- Dorico keeps one Lua state between runs: reload our modules
  if package.searchpath(name, mine) then package.loaded[name] = nil end
end
if not package.path:find(mine, 1, true) then package.path = mine .. ";" .. package.path end
local probe = require("probe")
local chartflow = require("chartflow")
local events = require("events")

local trail = io.open(os.getenv("TEMP") .. "/hbuc-run/progress.txt", "w")
local function mark(...)
  local t = {}
  for i = 1, select("#", ...) do t[#t + 1] = tostring(select(i, ...)) end
  trail:write(table.concat(t, "\t"), "\n"); trail:flush()
end

local RL = function(n, d) if d then return DoCore.RhythmicLength(n, d) end return DoCore.RhythmicLength(n) end

probe.run("01_pitch", function(p)
  local app = DoApp.DoApp()
  local ctx = DoCore.PropertyContext()
  mark("chart flow")
  local chart = chartflow.create(app, "Handbells Used Chart")
  mark("chart player")
  chartflow.addChartPlayer(app, chart, "instrument.pitchedpercussion.handbells")
  for _, f in ipairs(app.currentScore.flows) do if f.id == chart.id then chart = f end end
  local voices = chart.voiceStreams
  p:check("chart player has two voice streams", #voices == 2, #voices)
  local treble, bass = voices[1], voices[2]
  p:fact("voiceStreams", { tostring(treble), tostring(bass) })

  -- sounding spellings for the written targets (handbells sound an octave up)
  local writes = {
    { voice = treble, pos = 0, sounding = "C5", written = "C4" },
    { voice = treble, pos = 1, sounding = "Ab5", written = "Ab4" },
    { voice = treble, pos = 2, sounding = "G#5", written = "G#4" },
    { voice = treble, pos = 3, sounding = "G5", written = "G4 (natural after G#)" },
    { voice = treble, pos = 4, sounding = "D8", written = "D7" },
    { voice = treble, pos = 5, sounding = "E6", written = "E5 (chord)" },
    { voice = treble, pos = 5, sounding = "G#6", written = "G#5 (chord)" },
    { voice = bass, pos = 0, sounding = "Bb3", written = "Bb2" },
  }
  local made = {}
  for i, w in ipairs(writes) do
    mark("fromString", w.sounding)
    local okS, pitch = pcall(DoCore.MIDIPitchWithSpelling.fromString, w.sounding)
    if not okS then p:check("fromString(" .. w.sounding .. ")", false, pitch) return end
    mark("createNote", w.sounding)
    local okN, ev = pcall(function() return w.voice:createNote(RL(w.pos), RL(1), pitch) end)
    p:check("createNote " .. w.written, okN, okN and tostring(ev) or ev)
    made[i] = okN and ev or nil
  end

  -- read back from the stream, not the returned wrapper
  local back = {}
  for _, v in ipairs({ treble, bass }) do
    for _, e in ipairs(v.events) do
      local ev = events.parse(tostring(e))
      if ev.kind == "note" then
        back[#back + 1] = ev.pos .. ":" .. ev.spelling .. "=" .. tostring(e.propertyTable:get("kNotePitch", ctx))
      end
    end
  end
  p:fact("readBack", back)
  -- each written note reads back with the spelling it was given (chord notes share a position)
  for _, w in ipairs(writes) do
    local found = false
    for _, e in ipairs(w.voice.events) do
      local ev = events.parse(tostring(e))
      if ev.kind == "note" and ev.pos == w.pos and ev.spelling == w.sounding then found = true end
    end
    p:check("reads back as " .. w.sounding .. ": " .. w.written, found)
  end

  local function set(e, name, variant, label)
    local ok, res = pcall(function() return e.propertyTable:set(name, variant, ctx) end)
    local now = tostring(e.propertyTable:get(name, ctx))
    p:fact(label, tostring(ok) .. "/" .. tostring(res) .. " -> '" .. now .. "'")
    return ok and res
  end
  mark("stems")
  if made[1] then set(made[1], "kNoteHideStem", DoCore.Variant.createString("true"), "hideStemString") end
  if made[2] then set(made[2], "kNoteHideStem", DoCore.Variant.createBool(true), "hideStemBool") end
  for i = 3, #writes do
    if made[i] then set(made[i], "kNoteHideStem", DoCore.Variant.createString("true"), "hideStem" .. i) end
  end
  mark("accidentals")
  if made[4] then set(made[4], "kNoteAccidentalVisibility", DoCore.Variant.createString("kHide"), "hideNatural") end
  if made[3] then set(made[3], "kNoteAccidentalVisibility", DoCore.Variant.createString("kShow"), "showSharp") end

  mark("texts")
  local okL, label = pcall(function() return treble:createText(RL(0), RL(1), "Handbells Used: 5") end)
  p:check("label text", okL, tostring(label))
  local okM, marker = pcall(function() return treble:createText(RL(6), RL(1), "HBUC|1|probe") end)
  p:check("marker text", okM, tostring(marker))
  if okM then set(marker, "kEventHide", DoCore.Variant.createString("true"), "hideMarker") end
  p:fact("chartFlowId", chart.id)
  mark("done")
end)
trail:close()
