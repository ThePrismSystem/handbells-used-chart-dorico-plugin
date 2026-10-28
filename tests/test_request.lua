-- The dialog protocol: what Lua sends the dialog, how its answer is read back, and what is remembered. Ported in
-- spirit from the Sibelius plugin's ReadOptions (src/Options.mss).
local request = require("hbuc.request")
local constants = require("hbuc.constants")
local options = require("hbuc.options")

local NONE, MATCH = constants.NO_NOTEHEAD, constants.SHAPE_MATCH
local NORMAL, DIAMOND, SQUARE = "noteheadset.default", "noteheadset.diamondNoteheads", "noteheadset.rectangular"

local function rec(head, colour, instrument)
  return { pitch = 72, diatonic = 35, head = head, colour = colour or "", instrument = instrument or "A" }
end

local RECORDS = {
  rec(NORMAL), rec(DIAMOND, "#c80000"), rec(DIAMOND, "#c80000"), rec(DIAMOND), rec(SQUARE, "#008000", "B"),
  { instrument = "B", head = "", colour = "" }, -- an unread note: no head to offer
}

local function build(settingsText, players)
  return request.build({
    players = players or { "A", "B", "Organ" },
    records = RECORDS,
    settings = options.decodeSettings(settingsText),
    chartExists = false,
    runId = "r1",
  })
end

local function kindRow(req, kind)
  for _, k in ipairs(req.kinds) do
    if k.kind == kind then return k end
  end
end

local function answer(over)
  local raw = {
    version = constants.VERSION, cancelled = false, instruments = { "A", "B" }, mode = constants.CHART_MODE_COMBINED,
    heads = { bells = NORMAL, chimes = DIAMOND, smbs = SQUARE, pf = NONE, whitechapel = NONE },
    shapes = { bells = MATCH, chimes = MATCH, smbs = "Square", pf = MATCH, whitechapel = MATCH },
    colours = { chimes = "#c80000", smbs = "", pf = "", whitechapel = "" },
    remove = false, runId = "r1", atPitch = {},
  }
  for k, v in pairs(over or {}) do raw[k] = v end
  return raw
end

return {
  constants_for_the_dialog = function(t)
    t:eq(constants.VERSION, "0.1.0")
    t:eq(constants.DIALOG.title, "Create a Handbells/Handchimes/SMBs Used Chart")
    t:eq(constants.DIALOG.saveNote, "The project is saved before the chart is drawn.")
    t:eq(constants.DIALOG.newPage, "Start the music on a new page")
    t:eq(constants.KIND_COLOUR_LABEL.chimes, "Handchime Color")
    t:eq(constants.KIND_COLOUR_LABEL.bells, nil)
  end,
  choices_list_heads_in_order_with_defaults = function(t)
    local c = request.choices(RECORDS)
    t:eq(#c.heads, 3)
    t:eq(c.heads[1], NORMAL)
    t:eq(c.heads[2], DIAMOND)
    t:eq(c.heads[3], SQUARE)
    t:eq(c.defaultBell, NORMAL)
    t:eq(c.defaultChime, DIAMOND)
    t:eq(options.mostUsedColour(c.tally, DIAMOND), "#c80000")
    t:eq(request.choices({ rec(SQUARE) }).defaultBell, "")
  end,
  colours_lua_cannot_read_do_not_vote = function(t)
    -- Coloured by command, as in the Properties panel: the notes have a colour, but it reads as "", which would
    -- otherwise count as black.
    local unreadable = rec(DIAMOND)
    unreadable.colourUnreadable = true
    local c = request.choices({ rec(DIAMOND, "#c80000"), unreadable, unreadable, rec(SQUARE), unreadable })
    t:eq(options.mostUsedColour(c.tally, DIAMOND), "#c80000")
    t:eq(c.heads[1], DIAMOND, "the head is still offered")
    local only = request.choices({ unreadable })
    t:eq(only.heads[1], DIAMOND)
    t:eq(options.mostUsedColour(only.tally, DIAMOND), "", "nothing to suggest")
  end,
  build_lists_noteheads_by_name = function(t)
    local req = build("")
    t:eq(req.version, constants.VERSION)
    t:eq(req.noteheads[1].id, NONE)
    t:eq(req.noteheads[1].name, NONE)
    t:eq(req.noteheads[2].id, NORMAL)
    t:eq(req.noteheads[2].name, "Default Noteheads")
    t:eq(req.noteheads[3].name, "Diamond Noteheads")
    t:eq(#req.shapes, 8)
    t:eq(req.modes[1], constants.CHART_MODE_COMBINED)
    t:eq(req.mode, constants.CHART_MODE_COMBINED)
  end,
  build_preselects_all_but_excluded = function(t)
    local req = build('{"excluded":"Organ"}')
    t:eq(#req.instruments, 3)
    t:eq(#req.selected, 2)
    t:eq(req.selected[1], "A")
    t:eq(req.selected[2], "B")
  end,
  build_opens_remembered_head_only_if_used = function(t)
    t:eq(kindRow(build('{"heads":{"smbs":"noteheadset.rectangular"}}'), "smbs").head, SQUARE)
    t:eq(kindRow(build('{"heads":{"smbs":"noteheadset.Xnoteheads"}}'), "smbs").head, NONE, "not in this score")
    t:eq(kindRow(build(""), "bells").head, NORMAL, "the plain head suggests bells")
    t:eq(kindRow(build(""), "chimes").head, DIAMOND, "the diamond suggests chimes")
    t:eq(kindRow(build(""), "pf").head, NONE, "nothing suggests P&F")
  end,
  build_fills_colour_from_majority = function(t)
    t:eq(kindRow(build(""), "chimes").colour, "#c80000")
    t:eq(kindRow(build('{"colours":{"chimes":"#0000ff"}}'), "chimes").colour, "#0000ff", "a remembered colour wins")
    t:eq(build("").colours[SQUARE], "#008000")
  end,
  bells_have_no_colour_field = function(t)
    local row = kindRow(build(""), "bells")
    t:eq(row.colourLabel, nil)
    t:eq(row.colour, nil)
    t:eq(kindRow(build(""), "smbs").colourLabel, "SMBs Color")
  end,
  remembered_mode_and_shape = function(t)
    local req = build('{"mode":"separate","shapes":{"bells":"Diamond","chimes":"Hexagon"}}')
    t:eq(req.mode, constants.CHART_MODE_SEPARATE)
    t:eq(kindRow(req, "bells").shape, "Diamond")
    t:eq(kindRow(req, "chimes").shape, MATCH)
  end,
  cancelled_or_missing_or_wrong_version_is_nil = function(t)
    local req = build("")
    t:eq(request.parse(nil, req), nil)
    t:eq(request.parse({ cancelled = true, version = constants.VERSION }, req), nil)
    t:eq(request.parse(answer({ version = "0.0.9" }), req), nil)
    t:eq(request.parse("not a table", req), nil)
  end,
  parse_reads_the_answer = function(t)
    local resp = request.parse(answer(), build(""))
    t:eq(#resp.instruments, 2)
    t:eq(resp.mode, "combined")
    t:eq(resp.heads.chimes, DIAMOND)
    t:eq(resp.shapes.smbs, "Square")
    t:eq(resp.colours.chimes, "#c80000")
    t:eq(resp.remove, false)
  end,
  response_accepts_bare_strings_and_empty_objects = function(t)
    local req = build("")
    t:eq(#request.parse(answer({ instruments = "A" }), req).instruments, 1)
    t:eq(request.parse(answer({ instruments = "A" }), req).instruments[1], "A")
    t:eq(#request.parse(answer({ instruments = {} }), req).instruments, 0)
  end,
  unknown_values_fall_back = function(t)
    local resp = request.parse(answer({
      instruments = { "B", "Ghost", "A" },
      heads = { bells = "noteheadset.Xnoteheads" },
      shapes = { bells = "Hexagon" },
      colours = { chimes = " c80000 " },
    }), build(""))
    t:eq(#resp.instruments, 2, "an unknown instrument is dropped")
    t:eq(resp.instruments[1], "A", "score order")
    t:eq(resp.heads.bells, NONE)
    t:eq(resp.heads.chimes, NONE, "a missing head is no head")
    t:eq(resp.shapes.bells, MATCH)
    t:eq(resp.colours.chimes, "#c80000")
  end,
  mode_text_maps_to_mode = function(t)
    t:eq(request.parse(answer({ mode = constants.CHART_MODE_SEPARATE }), build("")).mode, "separate")
    t:eq(request.parse(answer({ mode = "nonsense" }), build("")).mode, "combined")
    t:eq(request.parse(answer({ remove = true }), build("")).remove, true)
  end,
  build_opens_on_a_new_page_unless_remembered_otherwise = function(t)
    t:eq(build("").newPage, true, "Dorico's own layout: the music after the chart starts a new page")
    t:eq(build('{"newPage": false}').newPage, false)
  end,
  parse_reads_new_page = function(t)
    t:eq(request.parse(answer({ newPage = false }), build("")).newPage, false)
    t:eq(request.parse(answer({ newPage = true }), build("")).newPage, true)
    t:eq(request.parse(answer(), build("")).newPage, true, "an answer without it keeps the new page")
    t:eq(request.parse(answer({ newPage = "no" }), build("")).newPage, true, "only false turns it off")
  end,
  settings_after_remember_new_page = function(t)
    local req = build("")
    local resp = request.parse(answer({ newPage = false }), req)
    local after = request.settingsAfter(options.decodeSettings(""), req, resp)
    t:eq(after.newPage, false)
    t:eq(options.decodeSettings(options.encodeSettings(after)).newPage, false, "survives the settings file")
  end,
  settings_after_remember_exclusions_and_choices = function(t)
    local settings = options.decodeSettings('{"excluded":"Elsewhere"}')
    local req = build("")
    local resp = request.parse(answer({ instruments = { "A" }, mode = constants.CHART_MODE_SEPARATE }), req)
    local after = request.settingsAfter(settings, req, resp)
    t:eq(after.excluded, "Elsewhere|B|Organ")
    t:eq(after.mode, "separate")
    t:eq(after.heads.chimes, DIAMOND)
    t:eq(after.shapes.smbs, "Square")
    t:eq(after.colours.chimes, "#c80000")
    local round = options.decodeSettings(options.encodeSettings(after))
    t:eq(round.excluded, "Elsewhere|B|Organ", "survives the settings file")
  end,
  build_offers_remembered_at_pitch_names = function(t)
    local req = build('{"atPitch":"Organ|Gone"}')
    t:eq(req.runId, "r1")
    t:eq(#req.atPitch, 1, "a remembered name this score doesn't offer stays out")
    t:eq(req.atPitch[1], "Organ")
    t:eq(#build("").atPitch, 0)
    t:eq(constants.DIALOG.writtenHeader, "Written as")
    t:eq(constants.DIALOG.writtenHandbells, "Handbells instrument (sounds an octave higher)")
    t:eq(constants.DIALOG.writtenAtPitch, "At pitch (e.g. Piano or Organ)")
    t:eq(constants.DIALOG.chartColumn, "Chart")
    t:eq(constants.DIALOG.instrumentColumn, "Instrument")
  end,
  response_reads_at_pitch_like_instruments = function(t)
    local req = build("")
    t:eq(request.parse(answer({ atPitch = "Organ" }), req).atPitch[1], "Organ", "a bare string is one name")
    t:eq(#request.parse(answer({ atPitch = {} }), req).atPitch, 0)
    local resp = request.parse(answer({ atPitch = { "Organ", "Ghost", "A" } }), req)
    t:eq(#resp.atPitch, 2, "an unknown name is dropped")
    t:eq(resp.atPitch[1], "A", "score order")
    t:eq(#request.parse(answer({ atPitch = nil }), req).atPitch, 0, "missing is none")
  end,
  response_with_another_run_id_is_a_cancel = function(t)
    local req = build("")
    t:eq(request.parse(answer({ runId = "old" }), req), nil)
    t:eq(request.parse(answer({ runId = false }), req), nil)
    local noId = request.build({ players = { "A" }, records = RECORDS, settings = options.decodeSettings(""),
      chartExists = false })
    t:eq(request.parse(answer({ runId = nil }), noId), nil, "a request without a run id accepts nothing")
  end,
  settings_after_remember_at_pitch = function(t)
    local settings = options.decodeSettings('{"atPitch":"Elsewhere|A"}')
    local req = build("")
    local resp = request.parse(answer({ atPitch = { "Organ" } }), req)
    t:eq(request.settingsAfter(settings, req, resp).atPitch, "Elsewhere|Organ")
  end,
}
