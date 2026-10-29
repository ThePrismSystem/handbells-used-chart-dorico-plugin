-- Can a run write the project's current state to another file without retargeting the project? On a scratch copy:
-- sets a notehead by command (an unsaved change), then tries args.command (default File.Save with a File parameter)
-- to args.file, and reports the project's path before and after, both files' modification times, and the overload
-- lists of DoApp's save and open.
--   python tools/dorico/run_lua.py spike/52_save_copy.lua --open fixtures/handbells-fixture.dorico --args "{...}"
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])")
local repo = here .. "../"
local mine = here .. "lib/?.lua;" .. repo .. "tests/dorico/lib/?.lua;" .. repo .. "plugin/Handbells Used Chart/?.lua"
for name in pairs(package.loaded) do
  if name:match("^hbuc") or package.searchpath(name, mine) then package.loaded[name] = nil end
end
if not package.path:find(mine, 1, true) then package.path = mine .. ";" .. package.path end
local probe = require("probe")

local function candidates(fn, ...)
  local ok, err = pcall(fn, ...)
  if ok then return "accepted" end
  return (tostring(err):gsub("No matching overload found, candidates:\n", ""))
end

probe.run("52_save_copy", function(p)
  local cases = require("cases")
  local commands = require("hbuc.commands")
  local doc = require("hbuc.dorico.doc")
  local ctx = cases.context(p)
  local app, log = ctx.app, ctx.log

  local T = { {}, {}, {}, {}, {}, {}, {} }
  p:fact("signatures", {
    ["DoApp.save"] = candidates(function() return app.save(app, unpack(T)) end),
    ["DoApp.open"] = candidates(function() return app.open(app, unpack(T)) end),
  })

  local before = probe.projectPath(app)
  p:fact("pathBefore", before)
  p:fact("mtimeBefore", lfs.attributes(before, "modification"))

  -- args.step: "edit" or "save" alone (spike/52_save_copy.py looks at the window title in between), else both
  if p.args.step ~= "save" then
    local flow = app.currentScore.flows[1]
    local stream = doc.voiceOwners(flow)[1].stream
    local note
    for _, e in ipairs(stream.events) do
      if tostring(e):match("^kNoteEvent") then note = e break end
    end
    doc.select(app, log, flow.id, note.id, doc.blockIdOf(stream, note.id))
    doc.command(app, log, commands.build("Edit.SetNoteheadSetOverride",
      { { "NoteheadSetEntityID", "noteheadset.rectangular" } }))
    doc.command(app, log, "Edit.SelectNone")
    p:fact("noteId", note.id)
  end
  if p.args.step == "edit" then return end

  os.remove(p.args.file)
  if p.args.command == "lua" then
    local okSave, saved = pcall(function() return app:save(app.currentScore, p.args.file) end)
    p:fact("command", "app:save(score, file) -> " .. tostring(okSave) .. " " .. tostring(saved))
  else
    local cmd = commands.build(p.args.command or "File.Save", { { "File", p.args.file } })
    doc.command(app, log, cmd)
    p:fact("command", cmd)
  end

  local after = probe.projectPath(app)
  p:fact("pathAfter", after)
  p:fact("mtimeOriginalAfter", lfs.attributes(before, "modification"))
  p:fact("copyWritten", lfs.attributes(p.args.file, "modification") ~= nil)
  -- the runner closes the copy by score id, whatever its path now is
  p:check("project still points at the original", after == before, after)
end)
