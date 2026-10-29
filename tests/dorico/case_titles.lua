-- The flows' titles (text export), by flow number, on the scratch copy that is open. Read-only.
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

probe.run("case_titles", function(p)
  -- required here, not above: a module that fails to load is then reported, and the copy closed
  local cases = require("cases")
  local doc = require("hbuc.dorico.doc")
  local textexport = require("hbuc.textexport")
  local ctx = cases.context(p)
  -- args.renameFirstFlow: an edit of the user's own, in a script run of its own (so its own undo step)
  -- args.secondFlow: a second flow holding one note, the flow and the note together one undo step
  if p.args.secondFlow then
    local before = {}
    for _, f in ipairs(ctx.app.currentScore.flows) do before[f.id] = true end
    ctx.app:doCommand("Project.Flow.New")
    for _, f in ipairs(ctx.app.currentScore.flows) do
      if not before[f.id] then
        f.voiceStreams[1]:createNote(DoCore.RhythmicLength(0), DoCore.RhythmicLength(1),
          DoCore.MIDIPitchWithSpelling.fromString("C5"))
      end
    end
  end
  if p.args.renameFirstFlow then
    ctx.app:doCommand(require("hbuc.commands").renameFlow(ctx.app.currentScore.flows[1].id, p.args.renameFirstFlow))
  end
  local titles = {}
  for n, title in pairs(textexport.flowTitles(doc.exportText(ctx.app, ctx.log, ctx.folders.temp, "titles"))) do
    titles[tostring(n)] = title
  end
  p:fact("titles", titles)
end)
