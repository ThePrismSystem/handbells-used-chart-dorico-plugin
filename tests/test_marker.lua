-- The chart's identity marker. Adapted from the Sibelius plugin's test/TestMarker.mss: the Dorico marker
-- records the chart players, one entry per section and the layout options to put back on removal.
local marker = require("hbuc.marker")

local function sample()
  return {
    version = "2",
    chartPlayers = { 3, 4 },
    sections = {
      { kind = "bells", player = 3, columns = 26 },
      { kind = "chimes", player = 3, columns = 10 },
      { kind = "smbs", player = 4, columns = 14 },
    },
    restore = {
      flowHeadingBehaviour = "kAlwaysInsertHeadings",
      hideEmptyStavesPolicy = "kNever",
      alwaysVisiblePlayers = "",
      playersToShowPlayerName = "",
      flowBreakBehaviour = "kStartNewPageForFlows",
    },
  }
end

local function same(t, a, b)
  t:eq(a.version, b.version, "version")
  t:eq(table.concat(a.chartPlayers, ","), table.concat(b.chartPlayers, ","), "chart players")
  t:eq(#a.sections, #b.sections, "section count")
  for i, s in ipairs(b.sections) do
    t:eq(a.sections[i].kind, s.kind, "section " .. i .. " kind")
    t:eq(a.sections[i].player, s.player, "section " .. i .. " player")
    t:eq(a.sections[i].columns, s.columns, "section " .. i .. " columns")
  end
  for k, v in pairs(b.restore) do t:eq(a.restore[k], v, "restore " .. k) end
end

return {
  round_trip = function(t)
    local text = marker.encode(sample())
    t:eq(text:sub(1, 7), "HBUC|2|", "prefix and version first")
    same(t, marker.decode(text), sample())
  end,
  flow_breaks_round_trip = function(t)
    local m = sample()
    m.restore.flowBreakBehaviour = "kNoFlowBreaks"
    t:eq(marker.decode(marker.encode(m)).restore.flowBreakBehaviour, "kNoFlowBreaks")
  end,
  version_1_markers_still_decode = function(t)
    -- written before the flow-break option: no flow-break value to put back
    local m = marker.decode("HBUC|1|3,4|1|bells,3,26|kAlwaysInsertHeadings|kNever|0,1|3,4")
    t:eq(m.version, "1")
    t:eq(m.restore.flowHeadingBehaviour, "kAlwaysInsertHeadings")
    t:eq(m.restore.playersToShowPlayerName, "3,4")
    t:eq(m.restore.flowBreakBehaviour, nil)
    t:eq(marker.decode("HBUC|1|3,4|1|bells,3,26|kAlwaysInsertHeadings|kNever|0,1|3,4|kNoFlowBreaks"), nil,
      "a version 1 marker has four layout values")
  end,
  restore_lists_round_trip = function(t)
    local m = sample()
    m.restore.alwaysVisiblePlayers = "0,1,2"
    m.restore.playersToShowPlayerName = "7,8"
    same(t, marker.decode(marker.encode(m)), m)
  end,
  no_markdown_characters = function(t)
    local text = marker.encode(sample())
    t:ok(not text:find("[%*_{}]"), "marker text contains no Markdown characters: " .. text)
  end,
  tampered_markers_decode_to_nil = function(t)
    local good = marker.encode(sample())
    local tokens = {}
    for tok in (good .. "|"):gmatch("([^|]*)|") do tokens[#tokens + 1] = tok end
    local function with(i, value)
      local copy = {}
      for j, tok in ipairs(tokens) do copy[j] = tok end
      copy[i] = value
      return table.concat(copy, "|")
    end
    local bad = {
      ["wrong prefix"] = good:gsub("^HBUC", "HBUX"),
      ["wrong version"] = with(2, "3"),
      ["non-numeric player id"] = with(3, "3,x"),
      ["non-numeric section count"] = with(4, "three"),
      ["section count too high"] = with(4, "4"),
      ["unknown kind"] = with(5, "gongs,3,26"),
      ["non-numeric columns"] = with(5, "bells,3,many"),
      ["unknown heading value"] = with(#tokens - 4, "kSometimes"),
      ["unknown hide-empty value"] = with(#tokens - 3, "kWhenever"),
      ["non-numeric visible players"] = with(#tokens - 2, "0,piano"),
      ["unknown flow-break value"] = with(#tokens, "kSometimes"),
      ["no flow-break value"] = with(#tokens, ""),
      ["extra token"] = good .. "|extra",
      ["missing token"] = good:gsub("|[^|]*$", ""),
      ["empty"] = "",
      ["not a marker"] = "Handbells Used: 5",
    }
    for label, text in pairs(bad) do
      t:eq(marker.decode(text), nil, label)
    end
  end,
  encode_refuses_what_decode_would_reject = function(t)
    local function variant(change)
      local m = sample()
      change(m)
      return m
    end
    t:fails(function() marker.encode(variant(function(m) m.restore.flowHeadingBehaviour = nil end)) end, "missing restore value")
    t:fails(function() marker.encode(variant(function(m) m.restore.flowBreakBehaviour = nil end)) end,
      "missing flow breaks")
    t:fails(function() marker.encode(variant(function(m) m.chartPlayers = {} end)) end, "no chart players")
    t:fails(function() marker.encode(variant(function(m) m.sections = {} end)) end, "no sections")
    t:fails(function() marker.encode(variant(function(m) m.sections[1].kind = "gongs" end)) end, "unknown kind")
    t:fails(function() marker.encode(variant(function(m) m.sections[1].columns = 2.5 end)) end, "fractional columns")
  end,
  is_marker_text = function(t)
    t:ok(marker.isMarker(marker.encode(sample())))
    t:ok(not marker.isMarker("Handbells Used: 5"))
    t:ok(marker.isMarker("HBUC|9|anything"), "any HBUC text is ours to recognise, even one we cannot read")
  end,
  zero_columns_and_foreign_players_are_damaged = function(t)
    local text = marker.encode(sample())
    t:eq(marker.decode((text:gsub("bells,3,26", "bells,3,0"))), nil, "a section with no columns")
    t:eq(marker.decode((text:gsub("smbs,4,14", "smbs,9,14"))), nil, "a section on a player the chart does not list")
    local m = sample()
    m.sections[1].player = 9
    t:fails(function() marker.encode(m) end, "such a marker is never written")
  end,
}
