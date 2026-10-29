-- savedcopy.read on a scratch copy: every dumped note's notehead set as the saved copy gives it, in the full score
-- and the note's own block instance, and the dumped notes the copy has no event for.
--   args.folder: a folder (raw bytes, as lfs takes them) to make in the temp folder and save the copy in
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])")
local repo = here .. "../../"
local mine = here .. "lib/?.lua;" .. repo .. "spike/lib/?.lua;" .. repo .. "plugin/Handbells Used Chart/?.lua"
for name in pairs(package.loaded) do
  if name:match("^hbuc") or package.searchpath(name, mine) then package.loaded[name] = nil end
end
if not package.path:find(mine, 1, true) then package.path = mine .. ";" .. package.path end
local probe = require("probe")

probe.run("case_savedcopy", function(p)
  -- required here, not above: a module that fails to load is then reported, and the copy closed
  local cases = require("cases")
  local noteprops = require("hbuc.noteprops")
  local doc = require("hbuc.dorico.doc")
  local savedcopy = require("hbuc.dorico.savedcopy")
  local ctx = cases.context(p)
  local app = ctx.app
  local temp = ctx.folders.temp
  if p.args.folder then
    temp = temp .. p.args.folder .. "/"
    require("lfs").mkdir(temp)
  end
  local t0 = os.clock()
  local notes = savedcopy.read(app, ctx.log, temp)
  p:fact("seconds", os.clock() - t0)
  local layoutId = app.currentLayoutID
  local heads, missing, total = {}, 0, 0
  for _, flow in ipairs(app.currentScore.flows) do
    for _, s in ipairs(flow.voiceStreams) do
      local d = doc.dumpOf(s)
      for _, ev in ipairs(d.events) do
        if (ev.kind == "note" or ev.kind == "grace") and ev.spelling then
          total = total + 1
          local entries = notes[ev.id]
          if entries then
            local h = noteprops.head(entries, layoutId, ev.instance)
            heads[h] = (heads[h] or 0) + 1
          else
            missing = missing + 1
          end
        end
      end
    end
  end
  p:fact("heads", heads)
  p:fact("dumped", total)
  p:fact("missing", missing)
  p:check("every dumped note is in the copy", missing == 0, missing)
end)
