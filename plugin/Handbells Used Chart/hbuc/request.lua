-- The dialog protocol. Lua writes the request (what the score offers and what was remembered), the dialog script
-- writes the response, and parse reads it back defensively: the response comes from another program, and
-- PowerShell 5.1 writes a one-item list as a bare value and an empty list as {}. Follows the Sibelius plugin's
-- ReadOptions (src/Options.mss).
local constants = require("hbuc.constants")
local instruments = require("hbuc.instruments")
local options = require("hbuc.options")
local shapes = require("hbuc.shapes")

local request = {}

local PLAIN, DIAMOND = "noteheadset.default", "noteheadset.diamondNoteheads"

-- The notehead sets the music uses (first-seen order), each set's colour tally, and the two suggestions Sibelius
-- makes: the plain head for handbells and the diamond for handchimes, when the score uses them.
function request.choices(records)
  local heads, seen, tally = {}, {}, {}
  for _, r in ipairs(records) do
    local head = r.head or ""
    if head ~= "" then
      if not seen[head] then
        seen[head] = true
        heads[#heads + 1] = head
      end
      options.tallyColour(tally, head, r.colour or "")
    end
  end
  return {
    heads = heads,
    tally = tally,
    defaultBell = seen[PLAIN] and PLAIN or "",
    defaultChime = seen[DIAMOND] and DIAMOND or "",
  }
end

-- args: {players = {name...} in score order, records, settings (options.decodeSettings), chartExists, runId}.
-- runId is echoed by the dialog, so a response left over from another run is never taken as this one's.
function request.build(args)
  local settings = args.settings
  local c = request.choices(args.records or {})
  local fallback = { bells = c.defaultBell, chimes = c.defaultChime }

  local noteheads = { { id = constants.NO_NOTEHEAD, name = constants.NO_NOTEHEAD } }
  local colours = {}
  for _, id in ipairs(c.heads) do
    noteheads[#noteheads + 1] = { id = id, name = shapes.displayName(id) }
    colours[id] = options.mostUsedColour(c.tally, id)
  end

  local kinds = {}
  for _, kind in ipairs(constants.KINDS) do
    local head = options.preferredHead(c.heads, settings.heads[kind], fallback[kind] or "")
    local row = {
      kind = kind,
      label = constants.KIND_NAME[kind],
      head = head,
      shape = shapes.preferred(settings.shapes[kind]),
    }
    if constants.KIND_COLOUR_LABEL[kind] then
      row.colourLabel = constants.KIND_COLOUR_LABEL[kind]
      row.colour = options.openingColour(settings.colours[kind], c.tally, head)
    end
    kinds[#kinds + 1] = row
  end

  local players = args.players or {}
  return {
    version = constants.VERSION,
    runId = args.runId,
    title = constants.DIALOG.title,
    labels = constants.DIALOG,
    instruments = players,
    selected = options.preselected(players, options.pipeList(settings.excluded)),
    atPitch = instruments.named(players, options.pipeList(settings.atPitch or "")),
    modes = { constants.CHART_MODE_COMBINED, constants.CHART_MODE_SEPARATE },
    mode = settings.mode == "separate" and constants.CHART_MODE_SEPARATE or constants.CHART_MODE_COMBINED,
    noteheads = noteheads,
    shapes = shapes.items(),
    kinds = kinds,
    colours = colours,
    chartExists = args.chartExists and true or false,
  }
end

-- A list from the response: a bare string is one item; {} or anything else is none.
local function list(v)
  if type(v) == "string" then return { v } end
  local out = {}
  if type(v) == "table" then
    for _, x in ipairs(v) do
      if type(x) == "string" then out[#out + 1] = x end
    end
  end
  return out
end

local function field(t, key)
  local v = type(t) == "table" and t[key] or nil
  return type(v) == "string" and v or nil
end

-- The chosen options, or nil for a cancel, a missing or unreadable response, or another version's.
function request.parse(raw, req)
  if type(raw) ~= "table" or raw.cancelled == true or raw.version ~= constants.VERSION then return nil end
  if req.runId == nil or raw.runId ~= req.runId then return nil end
  local offeredHeads, offeredShapes = {}, {}
  for _, h in ipairs(req.noteheads) do offeredHeads[h.id] = true end
  for _, s in ipairs(req.shapes) do offeredShapes[s] = true end

  local heads, chosenShapes, colours = {}, {}, {}
  for _, kind in ipairs(constants.KINDS) do
    local head = field(raw.heads, kind)
    heads[kind] = (head and offeredHeads[head]) and head or constants.NO_NOTEHEAD
    local shape = field(raw.shapes, kind)
    chosenShapes[kind] = (shape and offeredShapes[shape]) and shape or constants.SHAPE_MATCH
    if constants.KIND_COLOUR_LABEL[kind] then colours[kind] = options.usableColour(field(raw.colours, kind) or "") end
  end
  return {
    instruments = instruments.named(req.instruments, list(raw.instruments)),
    atPitch = instruments.named(req.instruments, list(raw.atPitch)),
    mode = options.chartModeOf(raw.mode),
    heads = heads,
    shapes = chosenShapes,
    colours = colours,
    remove = raw.remove == true,
  }
end

-- What to remember after a run, in the shape options.encodeSettings writes.
function request.settingsAfter(settings, req, resp)
  local excluded = options.excludedAfterRun(options.pipeList(settings.excluded), req.instruments, resp.instruments)
  return {
    excluded = options.joinPipe(excluded),
    atPitch = options.joinPipe(options.atPitchAfterRun(options.pipeList(settings.atPitch or ""), req.instruments,
      resp.atPitch or {})),
    mode = resp.mode,
    heads = resp.heads,
    shapes = resp.shapes,
    colours = resp.colours,
  }
end

return request
