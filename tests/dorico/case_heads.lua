-- Gives notes the notehead sets they already have again, but through Dorico's own command
-- (Edit.SetNoteheadSetOverride), as the Notations menu does. Lua can't read a set given that way
-- (spike/44_noteheads.lua), so the notes stand in for a score whose noteheads were changed in Dorico. In a run of
-- its own, so a later read's Edit.Undo can't take it back.
--   args.sets: the set ids to give again (default: every set but the default one)
--   args.first: {count, to}: the first count of those notes get set to instead
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])")
local repo = here .. "../../"
local mine = here .. "lib/?.lua;" .. repo .. "spike/lib/?.lua;" .. repo .. "plugin/Handbells Used Chart/?.lua"
for name in pairs(package.loaded) do
  if name:match("^hbuc") or package.searchpath(name, mine) then package.loaded[name] = nil end
end
if not package.path:find(mine, 1, true) then package.path = mine .. ";" .. package.path end
local probe = require("probe")

probe.run("case_heads", function(p)
  -- required here, not above: a module that fails to load is then reported, and the copy closed
  local cases = require("cases")
  local commands = require("hbuc.commands")
  local doc = require("hbuc.dorico.doc")
  local ctx = cases.context(p)
  local app = ctx.app
  local pctx = DoCore.PropertyContext()
  local wanted
  if p.args.sets then
    wanted = {}
    for _, id in ipairs(p.args.sets) do wanted[id] = true end
  end
  local redone = 0
  for _, flow in ipairs(app.currentScore.flows) do
    for _, s in ipairs(flow.voiceStreams) do
      local ok, list = pcall(function() return s.events end)
      if ok then
        local d = doc.dumpOf(s)
        for _, e in ipairs(list) do
          local head = tostring(e.propertyTable:get("kNoteheadSetOverride", pctx))
          local take = head ~= "" and (wanted and wanted[head] or (not wanted and head ~= "noteheadset.default"))
          if take and tostring(e):match("^k%a*NoteEvent") then
            doc.select(app, ctx.log, flow.id, e.id, doc.blockIdOf(s, e.id, d))
            -- the same set given again leaves the value Lua set, which it can still read: clear it first
            doc.command(app, ctx.log, "Edit.ClearNoteheadSetOverride")
            local first = p.args.first
            doc.command(app, ctx.log, commands.build("Edit.SetNoteheadSetOverride",
              { { "NoteheadSetEntityID", (first and redone < first.count) and first.to or head } }))
            redone = redone + 1
          end
        end
      end
    end
  end
  doc.command(app, ctx.log, "Edit.SelectNone")
  p:fact("redone", redone)
end)
