-- Draws a chart on a scratch copy of the fixture (every instrument selected) and checks it through the object
-- model. The driver checks the layout options through the Remote API and captures the page.
--   args.mode: "combined" (default) or "separate"
--   args.existing: true to find and update the chart already there
--   args.newPage: false to let the music follow the chart on its page
--   args.startBreaks: a flowBreakBehaviour to give the full score first, as the project's own
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])")
local repo = here .. "../../"
local mine = here .. "lib/?.lua;" .. repo .. "spike/lib/?.lua;" .. repo .. "plugin/Handbells Used Chart/?.lua"
for name in pairs(package.loaded) do
  if name:match("^hbuc") or package.searchpath(name, mine) then package.loaded[name] = nil end
end
if not package.path:find(mine, 1, true) then package.path = mine .. ";" .. package.path end
local probe = require("probe")

probe.run("case_write", function(p)
  -- required here, not above: a module that fails to load is then reported, and the copy closed
  local cases = require("cases")
  local chartcase = require("chartcase")
  local ctx = cases.context(p)
  if p.args.startBreaks then
    ctx.app:doCommand(require("hbuc.commands").layoutOptions(ctx.app.currentScore.openScoreID, 0,
      { flowBreakBehaviour = p.args.startBreaks }))
  end
  local out = chartcase.draw(p, ctx, { mode = p.args.mode or "combined", existing = p.args.existing,
    instruments = p.args.instruments, newPage = p.args.newPage })
  chartcase.check(p, ctx, out)
end)
