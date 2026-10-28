-- Removing a chart when the full score's layout cannot be found again, with hbuc.dorico.doc stubbed.
local function removeWith(layouts, opts)
  local sent = {}
  local fake = {
    command = function(_, _, c) sent[#sent + 1] = c end,
    flowById = function() return nil end,
    playerKey = function(pl) return pl.key end,
    layouts = function() return layouts end,
    playerIds = function() return {} end,
  }
  local savedDoc, savedRemove = package.loaded["hbuc.dorico.doc"], package.loaded["hbuc.dorico.removechart"]
  package.loaded["hbuc.dorico.doc"] = fake
  package.loaded["hbuc.dorico.removechart"] = nil
  local ok, result = pcall(function()
    local app = { currentScore = { openScoreID = 1, players = { { key = 10 }, { key = 7 } } } }
    local restore = { flowHeadingBehaviour = "kNever", hideEmptyStavesPolicy = "kNever", alwaysVisiblePlayers = "",
      playersToShowPlayerName = "" }
    for k, v in pairs(opts.restore or {}) do restore[k] = v end
    opts.restore = nil
    local found = { flowId = 4, marker = { chartPlayers = { 7 }, restore = restore } }
    opts.log = { line = function() end }
    return require("hbuc.dorico.removechart").remove(app, found, opts)
  end)
  package.loaded["hbuc.dorico.doc"], package.loaded["hbuc.dorico.removechart"] = savedDoc, savedRemove
  if not ok then error(result, 0) end
  local options = {}
  for _, c in ipairs(sent) do
    if c:find("^Project.Layout.SetOptions") then options[#options + 1] = c end
  end
  return result, options
end

return {
  no_full_score_is_reported = function(t)
    local result, options = removeWith({}, {})
    t:eq(result.removed, true)
    t:eq(result.restored, false, "the layout options could not be put back")
    t:eq(#options, 0)
  end,
  the_run_s_full_score_is_the_fallback = function(t)
    local result, options = removeWith({}, { fullId = 0 })
    t:eq(result.restored, true)
    t:eq(#options, 1)
    t:ok(options[1]:find("LayoutIDArray=0$"), options[1])
  end,
  flow_breaks_are_put_back = function(t)
    local _, options = removeWith({}, { fullId = 0, restore = { flowBreakBehaviour = "kNoFlowBreaks" } })
    t:ok(options[1]:find('{string: "flowBreakBehaviour"}\\, {string: "kNoFlowBreaks"}', 1, true), options[1])
  end,
  a_version_1_marker_leaves_flow_breaks_alone = function(t)
    -- it never changed them
    local _, options = removeWith({}, { fullId = 0 })
    t:ok(not options[1]:find("flowBreakBehaviour", 1, true), options[1])
  end,
  the_message = function(t)
    t:eq(require("hbuc.constants").MESSAGES.chartRemovedOptionsLeft, "The existing chart was removed, but the full"
      .. " score's layout options could not be put back as they were: check its flow headings, whether flows start"
      .. " on a new page, hidden staves and staff labels in Layout Options.")
  end,
}
