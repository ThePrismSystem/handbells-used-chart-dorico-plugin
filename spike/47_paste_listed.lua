-- Does the pasted copy readscore reads most scores through keep a UI-set notehead listed? On a scratch copy of the
-- fixture, in two runs:
--   args.step = "set": gives the first three notes of the first voice notehead sets by command
--     (Edit.SetNoteheadSetOverride: diamond, X, diamond), which read back unreadable like sets chosen in the UI.
--   args.step = "read": counts, in the music flow and then in a pasted copy made the way readscore makes it, the
--     notes that list kNoteheadSetOverride and how it reads. One Edit.Undo takes the copy away.
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])")
local repo = here .. "../"
local mine = here .. "lib/?.lua;" .. repo .. "tests/dorico/lib/?.lua;" .. repo .. "plugin/Handbells Used Chart/?.lua"
for name in pairs(package.loaded) do
  if name:match("^hbuc") or package.searchpath(name, mine) then package.loaded[name] = nil end
end
if not package.path:find(mine, 1, true) then package.path = mine .. ";" .. package.path end
local probe = require("probe")

-- {listedReadable, listedUnreadable, notes} over a flow's voice streams
local function tally(flow)
  local pctx = DoCore.PropertyContext()
  local out = { notes = 0, listedReadable = 0, listedUnreadable = 0, values = {} }
  for _, s in ipairs(flow.voiceStreams) do
    local ok, list = pcall(function() return s.events end)
    if ok then
      for _, e in ipairs(list) do
        if tostring(e):match("^kNoteEvent") then
          out.notes = out.notes + 1
          for _, n in ipairs(e.propertyTable:getPropertyNames()) do
            if n == "kNoteheadSetOverride" then
              local v = tostring(e.propertyTable:get(n, pctx))
              if v == "" then out.listedUnreadable = out.listedUnreadable + 1 else out.listedReadable = out.listedReadable + 1 end
              out.values[v] = (out.values[v] or 0) + 1
            end
          end
        end
      end
    else
      out.unlistable = (out.unlistable or 0) + 1
    end
  end
  return out
end

-- The first event of a parsed dump that a selection can start from (a note, grace note or rest).
local function firstEvent(parsed)
  for _, ev in ipairs(parsed.events) do
    if ev.kind == "note" or ev.kind == "grace" or ev.kind == "rest" then return ev.id end
  end
  return nil
end

probe.run("47_paste_listed", function(p)
  local cases = require("cases")
  local commands = require("hbuc.commands")
  local dump = require("hbuc.dump")
  local doc = require("hbuc.dorico.doc")
  local ctx = cases.context(p)
  local app, log = ctx.app, ctx.log
  local flow = app.currentScore.flows[1]

  if p.args.step == "set" then
    local stream = flow.voiceStreams[1]
    local d = doc.dumpOf(stream)
    local notes = dump.notes(d)
    for i, id in ipairs({ "noteheadset.diamondNoteheads", "noteheadset.Xnoteheads", "noteheadset.diamondNoteheads" }) do
      doc.select(app, log, flow.id, notes[i].id, doc.blockIdOf(stream, notes[i].id, d))
      doc.command(app, log, commands.build("Edit.SetNoteheadSetOverride", { { "NoteheadSetEntityID", id } }))
    end
    doc.command(app, log, "Edit.SelectNone")
    return
  end

  p:fact("music", tally(flow))
  local existing = {}
  for _, f in ipairs(app.currentScore.flows) do existing[f.id] = true end
  doc.command(app, log, "Project.Flow.New")
  local scratchId
  for _, f in ipairs(app.currentScore.flows) do
    if not existing[f.id] then scratchId = f.id end
  end
  local ok, err = pcall(function()
    local owners = doc.voiceOwners(flow)
    local first = owners[1]
    local d = doc.dumpOf(first.stream)
    local firstId = firstEvent(d)
    doc.select(app, log, flow.id, firstId, doc.blockIdOf(first.stream, firstId, d))
    doc.command(app, log, "Edit.SelectToStartOfFlow")
    doc.command(app, log, "Edit.SelectAtEndOfFlow")
    for _ = 2, #flow.staveStreams do doc.command(app, log, "EventEdit.NavigateDownExtend") end
    doc.command(app, log, "Filter.NotesAndChords")
    doc.command(app, log, "Edit.Copy")
    local scratch = doc.flowById(app.currentScore, scratchId)
    local top
    for _, o in ipairs(doc.voiceOwners(scratch)) do
      if o.key == first.key then top = o.stream break end
    end
    local temp = top:createNote(DoCore.RhythmicLength(0), DoCore.RhythmicLength(1),
      DoCore.MIDIPitchWithSpelling.fromString("C5"))
    doc.select(app, log, scratchId, temp.id, doc.blockIdOf(top, temp.id))
    doc.command(app, log, "Edit.Paste")
    doc.command(app, log, "Edit.SelectNone")
    p:fact("copy", tally(doc.flowById(app.currentScore, scratchId)))
  end)
  doc.command(app, log, "Edit.Undo")
  p:check("the copy is gone", doc.flowById(app.currentScore, scratchId) == nil)
  if not ok then error(err, 0) end
end)
