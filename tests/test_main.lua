-- main.run's last resort, with main.chart replaced: what the user is told depends on whether the project had been
-- saved when the run failed.
local main = require("hbuc.main")

local function runWith(chart)
  local ctx = { app = { versionString = "6.0.10" }, log = { path = "run.log", line = function() end } }
  ctx.show = function(kind, text) ctx.shown = { kind = kind, text = text } end
  local real = main.chart
  main.chart = chart
  local ok, out = pcall(main.run, ctx)
  main.chart = real
  if not ok then error(out, 0) end
  return ctx, out
end

return {
  failure_before_the_save_says_nothing_changed = function(t)
    local ctx, out = runWith(function() error("boom") end)
    t:eq(out.kind, "error")
    t:eq(out.text, "The plug-in stopped with an error, so nothing was changed: boom\n\nThe run log is at run.log.")
    t:eq(ctx.shown.text, out.text, "and shows it")
  end,
  failure_after_the_save_points_to_revert = function(t)
    local _, out = runWith(function(ctx) ctx.saved = true; error("boom") end)
    t:eq(out.text, "The chart could not be finished: boom\n\nUse File > Revert to return to the project as it was"
      .. " before the run. The run log is at run.log.")
  end,
}
