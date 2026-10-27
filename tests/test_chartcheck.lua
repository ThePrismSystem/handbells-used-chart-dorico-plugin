-- An existing chart is updated or removed only when its marker, its flow's title and its players all agree.
local chartcheck = require("hbuc.chartcheck")
local marker = require("hbuc.marker")
local constants = require("hbuc.constants")

local MARKER = marker.encode({
  chartPlayers = { 7, 8 },
  sections = { { kind = "bells", player = 7, columns = 5 } },
  restore = { flowHeadingBehaviour = "kAlwaysInsertHeadings", hideEmptyStavesPolicy = "kNever",
    alwaysVisiblePlayers = "", playersToShowPlayerName = "" },
})

local function info(over)
  local i = {
    markers = { { flowId = 4, text = MARKER } },
    flowTitles = { [4] = "Handbells Used Chart", [0] = "Song" },
    flowPlayers = { [4] = { 8, 7 }, [0] = { 0, 1, 2 } },
  }
  for k, v in pairs(over or {}) do i[k] = v end
  return i
end

return {
  chartcheck_flow_name_constant = function(t)
    t:eq(constants.CHART_FLOW_NAME, "Handbells Used Chart")
    t:eq(string.format(constants.CHART_PLAYER_LEFT, 2), "Handbells Used Chart 2")
  end,
  chartcheck_no_marker_is_none = function(t)
    t:eq(chartcheck.find(info({ markers = {} })).status, "none")
  end,
  chartcheck_valid_chart_is_ok = function(t)
    local r = chartcheck.find(info())
    t:eq(r.status, "ok")
    t:eq(r.flowId, 4)
    t:eq(r.marker.chartPlayers[1], 7)
    t:eq(r.marker.sections[1].columns, 5)
    t:eq(r.marker.restore.flowHeadingBehaviour, "kAlwaysInsertHeadings")
  end,
  chartcheck_two_markers_are_invalid = function(t)
    local r = chartcheck.find(info({ markers = { { flowId = 4, text = MARKER }, { flowId = 0, text = MARKER } } }))
    t:eq(r.status, "invalid")
    t:eq(r.reason, "there is more than one chart marker.")
  end,
  chartcheck_damaged_marker_is_invalid = function(t)
    local r = chartcheck.find(info({ markers = { { flowId = 4, text = "HBUC|1|7,8|x|bells,7,5" } } }))
    t:eq(r.status, "invalid")
    t:eq(r.reason, "its marker is damaged or was made by another version of the plug-in.")
  end,
  chartcheck_section_player_outside_the_chart_is_damaged = function(t)
    -- Written by hand: encode refuses to write such a marker.
    local odd = "HBUC|1|7,8|1|bells,9,5|kNoFlowHeadings|kNever||"
    local r = chartcheck.find(info({ markers = { { flowId = 4, text = odd } } }))
    t:eq(r.reason, "its marker is damaged or was made by another version of the plug-in.")
  end,
  chartcheck_renamed_flow_is_invalid = function(t)
    local r = chartcheck.find(info({ flowTitles = { [4] = "Chart", [0] = "Song" } }))
    t:eq(r.status, "invalid")
    t:eq(r.reason, 'the flow holding the chart is named "Chart", not "Handbells Used Chart".')
  end,
  chartcheck_unnumbered_titles_need_a_chart_title_somewhere = function(t)
    -- with no flow numbers in the export, the chart's title must at least be one of the flows' titles
    local ok = chartcheck.find(info({ flowTitles = {}, allTitles = { "Song", "Handbells Used Chart" } }))
    t:eq(ok.status, "ok")
    local r = chartcheck.find(info({ flowTitles = {}, allTitles = { "Song", "Chart" } }))
    t:eq(r.status, "invalid")
    t:eq(r.reason, 'no flow is named "Handbells Used Chart".')
  end,
  chartcheck_missing_chart_player_is_invalid = function(t)
    local r = chartcheck.find(info({ flowPlayers = { [4] = { 7 }, [0] = { 0 } } }))
    t:eq(r.status, "invalid")
    t:eq(r.reason, "the chart flow no longer holds every chart player.")
  end,
  chartcheck_a_new_player_in_the_chart_flow_is_tolerated = function(t)
    -- Dorico adds a new player to every flow, the chart's included
    local r = chartcheck.find(info({ flowPlayers = { [4] = { 7, 8, 9 }, [0] = { 0, 9 } } }))
    t:eq(r.status, "ok")
    t:eq(#r.extras, 1)
    t:eq(r.extras[1], 9)
  end,
  chartcheck_music_written_for_a_player_in_the_chart_flow_is_invalid = function(t)
    local r = chartcheck.find(info({
      flowPlayers = { [4] = { 7, 8, 9 }, [0] = { 0, 9 } },
      flowNotes = { [4] = { [9] = 3 } },
      playerNames = { [9] = "Flute" },
    }))
    t:eq(r.status, "invalid")
    t:eq(r.reason, 'the chart flow holds music for "Flute".')
  end,
  chartcheck_chart_player_in_a_new_flow_is_tolerated = function(t)
    -- a new flow holds every player, the chart's included
    local r = chartcheck.find(info({ flowPlayers = { [4] = { 7, 8 }, [0] = { 0 }, [5] = { 0, 7, 8 } } }))
    t:eq(r.status, "ok")
    t:eq(#r.strays, 2)
    t:eq(r.strays[1].flowId .. ":" .. r.strays[1].key, "5:7")
    t:eq(r.strays[2].flowId .. ":" .. r.strays[2].key, "5:8")
  end,
  chartcheck_chart_player_with_music_elsewhere_is_invalid = function(t)
    local r = chartcheck.find(info({
      flowPlayers = { [4] = { 7, 8 }, [0] = { 0, 8 } },
      flowNotes = { [0] = { [8] = 1 } },
      flowTitles = { [4] = "Handbells Used Chart", [0] = "Song" },
    }))
    t:eq(r.status, "invalid")
    t:eq(r.reason, 'a chart player has music in the flow "Song".')
  end,
}
