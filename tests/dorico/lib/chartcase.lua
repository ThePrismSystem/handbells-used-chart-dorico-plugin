-- Draws a chart with the plug-in's own modules (as main does after the dialog) and checks what was drawn through
-- the object model. Used by case_write.lua and the update cases.
local chartlayout = require("hbuc.chartlayout")
local constants = require("hbuc.constants")
local dump = require("hbuc.dump")
local eventtext = require("hbuc.eventtext")
local marker = require("hbuc.marker")
local plan = require("hbuc.plan")
local shapes = require("hbuc.shapes")
local textexport = require("hbuc.textexport")
local doc = require("hbuc.dorico.doc")
local readscore = require("hbuc.dorico.readscore")
local writechart = require("hbuc.dorico.writechart")

local chartcase = {}

-- The fixture's noteheads (fixtures/fixture_data.py) and the colours the dialog would open on.
chartcase.HEADS = {
  bells = "noteheadset.default", chimes = "noteheadset.diamondNoteheads", smbs = "noteheadset.rectangular",
  pf = "noteheadset.triangleDownNoteheads", whitechapel = "noteheadset.triangleUpNoteheads",
}
chartcase.COLOURS = { chimes = "#c80000", smbs = "#008000", pf = "#e628fa", whitechapel = "" }

local function musicParts(score, skip)
  local parts = {}
  for _, f in ipairs(score.flows) do
    if f.id ~= skip then
      local n = 0
      for _, s in ipairs(f.voiceStreams) do n = n + #dump.notes(doc.dumpOf(s)) end
      parts[f.id] = n .. "n/" .. #f.players .. "p"
    end
  end
  return parts
end

-- opts: {mode, existing (find and update the chart there), instruments (names; default all), newPage (false: no
-- flow breaks), lastStep (in place of chartlayout.LAST_STEP, for spike/41_last_step.py)}.
function chartcase.draw(p, ctx, opts)
  local app = ctx.app
  if opts.lastStep then chartlayout.LAST_STEP = opts.lastStep end
  local found
  if opts.existing then
    found = require("hbuc.dorico.findchart").find(app, ctx.log, ctx.folders.temp)
    p:fact("found", found.status .. (found.reason and (": " .. found.reason) or ""))
    if found.status ~= "ok" then error("no chart to update: " .. found.status) end
  end
  local skipKeys = {}
  if found then for _, k in ipairs(found.marker.chartPlayers) do skipKeys[k] = true end end
  local skipFlow = found and found.flowId
  local before = musicParts(app.currentScore, skipFlow)
  local namesBefore = {}
  for _, pl in ipairs(app.currentScore.players) do
    if not skipKeys[doc.playerKey(pl)] then namesBefore[doc.playerKey(pl)] = tostring(pl) end
  end

  local scan = readscore.scan(app, { log = ctx.log, skipFlowId = skipFlow, skipKeys = skipKeys,
    layoutId = app.currentLayoutID, tempDir = ctx.folders.temp })
  local names, musicKeys = {}, {}
  for _, pl in ipairs(scan.players) do
    names[#names + 1] = pl.name
    musicKeys[#musicKeys + 1] = pl.key
  end
  local thePlan = plan.build(scan.records, { heads = chartcase.HEADS, instruments = opts.instruments or names,
    mode = opts.mode })
  local slots = chartlayout.slots(thePlan.sections)
  local headNames = {}
  for _, id in pairs(chartcase.HEADS) do headNames[id] = shapes.displayName(id) end
  local shapeChoice = {}
  for _, kind in ipairs(constants.KINDS) do shapeChoice[kind] = constants.SHAPE_MATCH end
  local built = chartlayout.build(thePlan.sections, {
    shapes = shapeChoice, colours = chartcase.COLOURS, heads = chartcase.HEADS, headNames = headNames,
  })
  local t0 = os.clock()
  local res = writechart.write(app, built, { log = ctx.log, tempDir = ctx.folders.temp, slots = slots,
    musicKeys = musicKeys, existing = found, newPage = opts.newPage })
  p:fact("writeSeconds", os.clock() - t0)
  local labels = {}
  for _, s in ipairs(built.sections) do labels[#labels + 1] = s.label end
  p:fact("chartFlowId", res.flowId)
  p:fact("chartKeys", table.concat(res.chartKeys, ","))
  p:fact("slotKeys", table.concat(res.slotKeys, ","))
  p:fact("musicKeys", table.concat(musicKeys, ","))
  p:fact("musicIds", res.musicIds)
  p:fact("chartIds", res.chartIds)
  p:fact("labels", labels)
  p:fact("flowCount", #app.currentScore.flows)
  p:fact("playerCount", #app.currentScore.players)
  p:fact("layoutCount", #app.currentScore.layouts)
  return { built = built, res = res, before = before, musicKeys = musicKeys, namesBefore = namesBefore }
end

local function sortedJoin(list)
  table.sort(list)
  return table.concat(list, " ")
end

function chartcase.check(p, ctx, out)
  local app = ctx.app
  local score = app.currentScore
  local res, built = out.res, out.built
  local chart = doc.flowById(score, res.flowId)

  p:check("chart flow is first", score.flows[1].id == res.flowId)
  local titles = textexport.flowTitles(doc.exportText(app, ctx.log, ctx.folders.temp, "check-titles"))
  -- by position where the export numbers its flows; otherwise (Smith) the title must be among the flows' titles
  local titled = titles[1] == constants.CHART_FLOW_NAME
  if titles[1] == nil then
    for _, t in ipairs(titles.all) do
      if t == constants.CHART_FLOW_NAME then titled = true end
    end
  end
  p:check("chart flow is titled " .. constants.CHART_FLOW_NAME, titled, titles[1])
  local keys = {}
  for _, k in ipairs(doc.flowKeys(chart)) do keys[#keys + 1] = tostring(k) end
  local want = {}
  for _, k in ipairs(res.chartKeys) do want[#want + 1] = tostring(k) end
  p:check("chart flow holds exactly the chart players", sortedJoin(keys) == sortedJoin(want), sortedJoin(keys))

  -- marker and labels
  local markers, texts = {}, {}
  for _, s in ipairs(chart.voiceStreams) do
    for _, ev in ipairs(doc.dumpOf(s).events) do
      if ev.kind == "text" then
        if marker.isMarker(ev.text) then markers[#markers + 1] = ev.text else texts[#texts + 1] = ev.text end
      end
    end
  end
  p:check("one marker", #markers == 1, #markers)
  local m = markers[1] and marker.decode(markers[1])
  if p:check("marker decodes", m ~= nil, markers[1]) then
    local same = #m.sections == #built.sections
    for i, s in ipairs(built.sections) do
      local ms = m.sections[i]
      if not ms or ms.kind ~= s.kind or ms.columns ~= s.columns or ms.player ~= res.slotKeys[s.slot] then same = false end
    end
    p:check("marker sections match the chart", same)
    p:fact("restore", m.restore)
  end
  local labels = {}
  for _, s in ipairs(built.sections) do labels[#labels + 1] = s.label end
  p:check("one label per section", sortedJoin(texts) == sortedJoin(labels), sortedJoin(texts))

  -- notes: spelling, stem, notehead set and colour, on the right chart player and staff
  local expected = {}
  for _, s in ipairs(built.sections) do
    local key = res.slotKeys[s.slot]
    for staff, columns in ipairs({ s.treble, s.bass }) do
      for _, spellings in ipairs(columns) do
        for _, sp in ipairs(spellings) do
          expected[#expected + 1] = key .. ":" .. staff .. "|" .. sp .. "|" .. (s.noteheadSet or "") .. "|" .. s.colour
        end
      end
    end
  end
  local actual, stems, naturalsShown, restsLeft = {}, 0, 0, 0
  local index = {}
  for _, o in ipairs(doc.voiceOwners(chart)) do
    index[o.key] = (index[o.key] or 0) + 1
    for _, ev in ipairs(doc.dumpOf(o.stream).events) do
      if ev.kind == "rest" then restsLeft = restsLeft + 1 end
    end
    local ok, list = pcall(function() return o.stream.events end)
    if p:check("chart stream " .. o.stream.id .. " is readable", ok) then
      for _, e in ipairs(list) do
        local ev = eventtext.parse(tostring(e))
        if ev.kind == "note" and doc.getString(e, "kNoteHideNotehead") ~= "true" then
          actual[#actual + 1] = o.key .. ":" .. index[o.key] .. "|" .. ev.spelling .. "|"
            .. doc.getString(e, "kNoteheadSetOverride") .. "|" .. doc.getString(e, "kEventColour")
          if doc.getString(e, "kNoteHideStem") == "true" then stems = stems + 1 end
        end
        -- hidden notes too: a hidden notehead still shows its accidental (a natural after a flat in the bar)
        if ev.kind == "note" and ev.spelling:match("^[A-G]%-?%d+$") then
          local hidden = false
          for _, n in ipairs(e.propertyTable:getPropertyNames()) do
            if n == "kNoteAccidentalVisibility_v3" then hidden = true end
          end
          if not hidden then naturalsShown = naturalsShown + 1 end
        end
      end
    end
  end
  p:check("every chart note as planned", sortedJoin(actual) == sortedJoin(expected),
    #actual .. " drawn, " .. #expected .. " planned")
  p:check("every stem hidden", stems == #actual, stems)
  p:check("every natural hidden", naturalsShown == 0, naturalsShown)
  p:check("no rests in the chart", restsLeft == 0, restsLeft)

  local breaks, divisions = 0, 0
  for _, ev in ipairs(doc.dumpOf(chart.timebaseStreams[1]).events) do
    if ev.kind == "break" then breaks = breaks + 1 end
    if ev.kind == "bardivision" then divisions = divisions + 1 end
  end
  p:check("a system break before each section after the first", breaks == #built.sections - 1, breaks)
  p:check("a bar for each section", divisions == #built.sections - 1, divisions)

  local after = musicParts(app.currentScore, res.flowId)
  local same = true
  for id, part in pairs(out.before) do
    if after[id] ~= part then same = false end
  end
  p:check("the music is as it was", same)
  local probes = 0
  for _, f in ipairs(app.currentScore.flows) do
    for _, s in ipairs(f.voiceStreams) do
      for _, ev in ipairs(doc.dumpOf(s).events) do
        if ev.kind == "text" and ev.text == constants.PAGE_PROBE then probes = probes + 1 end
      end
    end
  end
  p:check("the page probe is gone", probes == 0, probes)
  local renamed = {}
  for key, name in pairs(out.namesBefore) do
    local pl = doc.playerByKey(app.currentScore, key)
    if not pl or tostring(pl) ~= name then renamed[#renamed + 1] = name end
  end
  p:check("every music player keeps its name", #renamed == 0, table.concat(renamed, ", "))
end

return chartcase
