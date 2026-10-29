-- Does a project saved with app:save name every notehead set chosen by command? On a scratch copy of the fixture,
-- driven by spike/53_dtn_survey.py:
--   step "setup": a new flow gets one C5 per set id in args.ids on the second player's first voice, each set by
--     Edit.SetNoteheadSetOverride as Dorico's UI does; every third note is also coloured by command. Reports
--     {eventId, head, colour} per note.
--   step "save": app:save(score, args.file), in a run of its own.
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])")
local repo = here .. "../"
local mine = here .. "lib/?.lua;" .. repo .. "tests/dorico/lib/?.lua;" .. repo .. "plugin/Handbells Used Chart/?.lua"
for name in pairs(package.loaded) do
  if name:match("^hbuc") or package.searchpath(name, mine) then package.loaded[name] = nil end
end
if not package.path:find(mine, 1, true) then package.path = mine .. ";" .. package.path end
local probe = require("probe")

probe.run("53_dtn_survey", function(p)
  local cases = require("cases")
  local commands = require("hbuc.commands")
  local doc = require("hbuc.dorico.doc")
  local ctx = cases.context(p)
  local app, log = ctx.app, ctx.log

  if p.args.step == "save" then
    local okSave, saved = pcall(function() return app:save(app.currentScore, p.args.file) end)
    p:check("app:save", okSave and saved == true, tostring(saved))
    return
  end

  local existing = {}
  for _, f in ipairs(app.currentScore.flows) do existing[f.id] = true end
  doc.command(app, log, "Project.Flow.New")
  local flowId
  for _, f in ipairs(app.currentScore.flows) do
    if not existing[f.id] then flowId = f.id end
  end
  if not flowId then error("Project.Flow.New did not add a flow") end

  local voices, seen = {}, {}
  for _, o in ipairs(doc.voiceOwners(doc.flowById(app.currentScore, flowId))) do
    if not seen[o.key] then
      seen[o.key] = true
      voices[#voices + 1] = o.stream
    end
  end
  local stream = voices[2]
  local notes = {}
  for i, id in ipairs(p.args.ids) do
    local e = stream:createNote(DoCore.RhythmicLength(i - 1), DoCore.RhythmicLength(1),
      DoCore.MIDIPitchWithSpelling.fromString("C5"))
    notes[i] = { eventId = e.id, head = id }
  end
  local parsed = doc.dumpOf(stream)
  for i, n in ipairs(notes) do
    doc.select(app, log, flowId, n.eventId, doc.blockIdOf(stream, n.eventId, parsed))
    doc.command(app, log, commands.build("Edit.SetNoteheadSetOverride", { { "NoteheadSetEntityID", n.head } }))
    if i % 3 == 0 then
      doc.command(app, log, "UI.InvokePropertyChangeValue?Type=kEventColour&Value=#ff00a050")
      n.colour = "#00a050"
    end
  end
  doc.command(app, log, "Edit.SelectNone")
  p:fact("flowId", flowId)
  p:fact("notes", notes)
end)
