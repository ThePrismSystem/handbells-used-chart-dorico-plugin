-- main.run on a scratch copy of the fixture whose noteheads were changed in Dorico (tests/dorico/case_heads.lua
-- first), with the MusicXML step answered as a director would. Dorico's own export and delete dialogs are answered by
-- tests/dorico/test_musicxml.py.
--   args.choose: the message's answers, in order ("export", "choose", "remove", "cancel"); then Cancel
--   args.pick: "preselected" (the files the picker selects) or "organ" (the Organ part's file from the export, a
--     player whose heads weren't changed); else none
--   args.expect: "drawn", "asksNothing", "mismatch" or "removed"
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])")
local repo = here .. "../../"
local mine = here .. "lib/?.lua;" .. repo .. "spike/lib/?.lua;" .. repo .. "plugin/Handbells Used Chart/?.lua"
for name in pairs(package.loaded) do
  if name:match("^hbuc") or package.searchpath(name, mine) then package.loaded[name] = nil end
end
if not package.path:find(mine, 1, true) then package.path = mine .. ";" .. package.path end
local probe = require("probe")

probe.run("case_musicxml", function(p)
  -- required here, not above: a module that fails to load is then reported, and the copy closed
  local cases = require("cases")
  local chartcase = require("chartcase")
  local constants = require("hbuc.constants")
  local files = require("hbuc.dorico.files")
  local findchart = require("hbuc.dorico.findchart")
  local main = require("hbuc.main")
  local readscore = require("hbuc.dorico.readscore")
  local M = constants.MESSAGES

  local answers, asked = p.args.choose or {}, 0
  local ctx = cases.context(p, {
    choose = function(choice)
      asked = asked + 1
      return answers[asked] or choice.cancel
    end,
    pick = function(pick)
      if p.args.pick == "preselected" then
        local paths = {}
        for i, name in ipairs(pick.files or {}) do paths[i] = pick.folder .. name end
        return paths
      end
      if p.args.pick == "organ" then
        for _, e in ipairs(files.exports(cases.runFolder()) or {}) do
          if e.path:find("Organ", 1, true) and not e.path:find(" - Full score - ", 1, true) then return { e.path } end
        end
      end
      return {}
    end,
    -- everything selected, each kind on the fixture's notehead (case_run.lua's "draw")
    respond = function(req)
      if p.args.expect ~= "drawn" then return nil end
      local shapes, colours = {}, {}
      for _, k in ipairs(req.kinds) do
        shapes[k.kind] = constants.SHAPE_MATCH
        if k.colourLabel then colours[k.kind] = k.colour or "" end
      end
      return { version = req.version, runId = req.runId, cancelled = false, instruments = req.instruments,
        mode = req.modes[1], heads = chartcase.HEADS, shapes = shapes, colours = colours, remove = false, atPitch = {} }
    end,
  })
  -- choices other cases left behind (an Organ-only run, say) would change what is charted
  os.remove(ctx.folders.data .. "settings.json")
  local summaryBefore = readscore.summary(ctx.app.currentScore)
  local out = main.run(ctx)
  local text = (p.facts.shown[#p.facts.shown] or {}).text or ""
  p:fact("outcome", out)
  p:fact("text", text)
  local heads = {}
  for _, h in ipairs((p.facts.request or {}).noteheads or {}) do heads[h.id] = true end
  local found = findchart.find(ctx.app, ctx.log, ctx.folders.temp)

  local expect = p.args.expect
  if expect == "drawn" then
    p:check("asked once", #p.facts.choices == 1, #p.facts.choices)
    p:check("the dropdown lists the diamond", heads["noteheadset.diamondNoteheads"] == true)
    p:check("a chart is there", found.status == "ok", found.status)
    p:check("reports the handchimes", text:find("Handchimes Used: 6", 1, true) ~= nil, text)
  elseif expect == "asksNothing" then
    p:check("asked nothing", #p.facts.choices == 0, #p.facts.choices)
    p:check("the dialog came", p.facts.request ~= nil)
  elseif expect == "mismatch" then
    p:check("says the export doesn't match", text == string.format(M.musicxmlMismatch, 1), text)
    p:check("no chart", found.status == "none", found.status)
    p:check("the music is as it was", readscore.summary(ctx.app.currentScore) == summaryBefore)
  elseif expect == "removed" then
    p:check("no options dialog", p.facts.request == nil)
    p:check("the choices are left as they were", files.read(ctx.folders.data .. "settings.json") == nil)
    p:check("removed", text == M.chartWasRemoved, text)
    p:check("no chart", found.status == "none", found.status)
  end
end)
