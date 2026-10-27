-- Takes a positively identified chart out again. Dorico confirms both deletions itself: the chart flow (its
-- "Delete Flow" dialog) and then the chart players, which are empty once the flow is gone ("Delete Empty
-- Players"). Lua and commands can't delete a player any other way (docs/dorico-lua-guide.md, section 5).
local chartlayout = require("hbuc.chartlayout")
local commands = require("hbuc.commands")
local constants = require("hbuc.constants")
local doc = require("hbuc.dorico.doc")

local removechart = {}

-- found: findchart's result with status "ok". opts: {log, fullId = the full score the run started on}. Returns
-- {removed = bool, restored = bool}: restored is false when no full score could be found to put its layout options
-- back on. Nothing else changes unless the user lets Dorico delete the flow.
function removechart.remove(app, found, opts)
  local log = opts.log
  local flowId = found.flowId
  local chartKeys = found.marker.chartPlayers
  doc.command(app, log, commands.setMode("kSetupMode"))
  doc.command(app, log, commands.deleteFlow(flowId))
  doc.command(app, log, commands.setMode("kWriteMode"))
  if doc.flowById(app.currentScore, flowId) then
    log:line("the chart flow was not deleted")
    return { removed = false }
  end

  local isChart, musicKeys = {}, {}
  for _, k in ipairs(chartKeys) do isChart[k] = true end
  for _, pl in ipairs(app.currentScore.players) do
    local k = doc.playerKey(pl)
    if not isChart[k] then musicKeys[#musicKeys + 1] = k end
  end
  local layouts = doc.layouts(app.currentScore)
  local fullId = chartlayout.fullScoreLayout(layouts, musicKeys) or opts.fullId
  local r = found.marker.restore
  if fullId then
    doc.command(app, log, commands.layoutOptions(app.currentScore.openScoreID, fullId, {
      flowHeadingBehaviour = r.flowHeadingBehaviour,
      hideEmptyStavesPolicy = r.hideEmptyStavesPolicy,
      alwaysVisiblePlayers = r.alwaysVisiblePlayers,
      ["staffLabelLayoutOptions.playersToShowPlayerName"] = r.playersToShowPlayerName,
    }))
    for _, id in ipairs(chartlayout.partLayouts(layouts, chartKeys, fullId)) do
      doc.command(app, log, commands.deleteLayout(id))
    end
  end
  -- Chart players are named with a space to hide their labels; named, they are recognisable in Dorico's list.
  local ids = doc.playerIds(app, log)
  for i, k in ipairs(chartKeys) do
    if ids[k] then doc.command(app, log, commands.renamePlayer(ids[k], string.format(constants.CHART_PLAYER_LEFT, i))) end
  end
  doc.command(app, log, "Project.Players.DeleteEmpty")
  if not fullId then log:line("no full-score layout was found, so its layout options were not put back") end
  return { removed = true, restored = fullId ~= nil }
end

return removechart
