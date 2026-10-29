-- Where the paste route pastes, against a fake score. The copied range starts on the staff of the flow's first note
-- or rest, so the paste has to start on that staff of the scratch flow too: pasted anywhere higher, every staff's
-- notes land one staff up and are credited to the wrong player.
local RULE = "------------------------------"

local function voice(id, spellings)
  local lines = { RULE, "Start block id: 1010 position: 0" }
  for i, sp in ipairs(spellings) do
    lines[#lines + 1] = string.format("%d (%d) dur: 1: kNoteEvent (id:%d) at %d, duration 1  %s (ends %d)",
      i - 1, i - 1, id * 100 + i, i - 1, sp, i)
  end
  local text = table.concat(lines, "\n") .. "\n"
  return { id = id, events = {}, blockInstances = { { id = 1010, block = { id = 10 } } },
    dump = function() return text end }
end

local function player(key)
  return setmetatable({ instruments = { { id = key } } }, { __tostring = function() return "Player " .. key end })
end

-- owners: the instrument key of each voice; notes: whether that voice has a note in the music flow. The scratch
-- flow gets scratchVoices voices for each player (one per staff, as Dorico makes a new flow).
local function pasteTarget(owners, notes, scratchVoices)
  local players, seen = {}, {}
  for _, key in ipairs(owners) do
    if not seen[key] then
      seen[key] = true
      players[#players + 1] = player(key)
    end
  end
  local music = { id = 0, players = players, voiceStreams = {}, instruments = {}, staveStreams = {} }
  for i, key in ipairs(owners) do
    music.voiceStreams[i] = voice(i, notes[i] and { "C5" } or {})
    music.instruments[i] = { id = key }
    music.staveStreams[i] = {}
  end
  local pastedOn
  local scratch = { id = 9, players = players, voiceStreams = {}, instruments = {}, removePlayer = function() end }
  for _, pl in ipairs(players) do
    local key = pl.instruments[1].id
    for n = 1, scratchVoices[key] do
      local s = voice(50 + #scratch.voiceStreams, {})
      local label = key .. ":" .. n
      s.createNote = function()
        pastedOn = label
        s.dump = function()
          return RULE .. "\nStart block id: 1010 position: 0\n0 (0) dur: 1: kNoteEvent (id:999) at 0, duration 1"
            .. "  C5 (ends 1)\n"
        end
        return { id = 999 }
      end
      scratch.voiceStreams[#scratch.voiceStreams + 1] = s
      scratch.instruments[#scratch.instruments + 1] = { id = key }
    end
  end
  local score = { players = players, flows = { music } }
  local app = { currentScore = score }
  function app.doCommand(_, c)
    if c == "Project.Flow.New" then score.flows[#score.flows + 1] = scratch end
    if c == "Edit.Undo" then score.flows[#score.flows] = nil end
  end

  local savedCore = DoCore
  DoCore = {
    PropertyContext = function() return {} end,
    RhythmicLength = function(n) return n end,
    MIDIPitchWithSpelling = { fromString = function(s) return s end },
  }
  package.loaded["hbuc.dorico.readscore"] = nil
  local ok, err = pcall(function()
    require("hbuc.dorico.readscore").scan(app, { log = { line = function() end }, forcePaste = true })
  end)
  DoCore = savedCore
  if not ok then error(err, 0) end
  return pastedOn
end

-- The positions the paste route reads for a flow whose one voice holds C5 and D5 from position lead on. Dorico pastes
-- the copy's first note at the scratch flow's start, wherever it was in the music (tests/dorico/test_read.py), and
-- so does this fake.
local function pastedPositions(lead)
  local function line(id, pos, spelling)
    return string.format("%d (%d) dur: 1: kNoteEvent (id:%d) at %d, duration 1  %s (ends %d)", pos, pos, id, pos,
      spelling, pos + 1)
  end
  local function event(id, pos, spelling)
    return setmetatable({ id = id, propertyTable = {
      getPropertyNames = function() return {} end,
      get = function() return "" end,
    } }, { __tostring = function() return (line(id, pos, spelling):gsub("^.-: (kNoteEvent)", "%1")) end })
  end
  local pl = player(1)
  local notes = voice(1, {})
  local text = table.concat({ RULE, "Start block id: 1010 position: 0", line(101, lead, "C5"), line(102, lead + 1, "D5") },
    "\n") .. "\n"
  notes.dump = function() return text end
  local music = { id = 0, players = { pl }, voiceStreams = { notes }, instruments = { { id = 1 } }, staveStreams = { {} } }
  local top = voice(50, {})
  top.createNote = function()
    top.dump = function() return RULE .. "\nStart block id: 1010 position: 0\n" .. line(999, 0, "C5") .. "\n" end
    return { id = 999 }
  end
  local scratch = { id = 9, players = { pl }, voiceStreams = { top }, instruments = { { id = 1 } },
    removePlayer = function() end }
  local score = { players = { pl }, flows = { music } }
  local app = { currentScore = score }
  function app.doCommand(_, c)
    if c == "Project.Flow.New" then score.flows[#score.flows + 1] = scratch end
    if c == "Edit.Paste" then top.events = { event(999, 0, "C5"), event(1, 0, "C5"), event(2, 1, "D5") } end
    if c == "Edit.Undo" then score.flows[#score.flows] = nil end
  end
  local savedCore = DoCore
  DoCore = {
    PropertyContext = function() return {} end,
    RhythmicLength = function(n) return n end,
    MIDIPitchWithSpelling = { fromString = function(s) return s end },
  }
  package.loaded["hbuc.dorico.readscore"] = nil
  local ok, scan = pcall(function()
    return require("hbuc.dorico.readscore").scan(app, { log = { line = function() end }, forcePaste = true })
  end)
  DoCore = savedCore
  if not ok then error(scan, 0) end
  local out = {}
  for _, n in ipairs(scan.read) do out[#out + 1] = n.spelling .. "@" .. tostring(n.pos) end
  return table.concat(out, ","), scan.pastedFlows
end

-- A flow Lua can list directly: one player, one voice, a note whose notehead was changed in Dorico (the property is
-- listed, but reads as "") and a plain one.
local function directScan()
  local function value(text) return setmetatable({}, { __tostring = function() return text end }) end
  local function event(text, names)
    return setmetatable({ propertyTable = {
      getPropertyNames = function() return names end,
      get = function() return value("") end,
    } }, { __tostring = function() return text end })
  end
  local stream = voice(1, { "C5", "D5" })
  stream.events = {
    event("kNoteEvent (id:101) at 0, duration 1  C5 (ends 1)", { "kNoteheadSetOverride" }),
    event("kNoteEvent (id:102) at 1, duration 1  D5 (ends 2)", {}),
  }
  local pl = player(1)
  local flow = { id = 7, players = { pl }, voiceStreams = { stream }, instruments = { { id = 1 } }, staveStreams = { {} } }
  local app = { currentScore = { players = { pl }, flows = { flow } }, doCommand = function() end }
  local savedCore = DoCore
  DoCore = { PropertyContext = function() return {} end }
  package.loaded["hbuc.dorico.readscore"] = nil
  local ok, scan = pcall(function()
    return require("hbuc.dorico.readscore").scan(app, { log = { line = function() end } })
  end)
  DoCore = savedCore
  if not ok then error(scan, 0) end
  return scan
end

return {
  scan_returns_positions_flows_and_unreadable_heads = function(t)
    local scan = directScan()
    t:eq(scan.pastedFlows, 0, "read directly")
    t:eq(#scan.read, 2)
    t:eq(scan.read[1].headUnreadable, true, "listed, but read as nothing")
    t:eq(scan.read[2].headUnreadable, false)
    t:eq(scan.read[1].pos, 0)
    t:eq(scan.read[2].pos, 1)
    t:eq(scan.read[1].flowId, 7)
    t:eq(#scan.dumped, 2)
    t:eq(scan.dumped[2].pos, 1)
    t:eq(scan.dumped[2].flowId, 7)
    t:eq(scan.dumped[2].instrument, "Player 1")
    t:eq(scan.flowNumbers[7], 1)
    t:eq(scan.records[1].head, "noteheadset.default", "until a MusicXML export says otherwise")
  end,
  the_paste_route_reads_the_music_s_own_positions = function(t)
    local positions, pasted = pastedPositions(0)
    t:eq(pasted, 1, "through a copy")
    t:eq(positions, "C5@0,D5@1")
    t:eq(pastedPositions(4), "C5@4,D5@5", "music that starts after four beats' rest on every staff")
  end,
  the_top_staff_when_the_first_player_plays = function(t)
    t:eq(pasteTarget({ 1, 1, 2, 2 }, { true, true, true, true }, { [1] = 2, [2] = 2 }), "1:1")
  end,
  the_next_player_when_the_first_is_tacet = function(t)
    t:eq(pasteTarget({ 1, 1, 2, 2 }, { false, false, true, true }, { [1] = 2, [2] = 2 }), "2:1")
  end,
  the_bass_staff_when_only_the_treble_is_empty = function(t)
    -- a grand staff's voices are [treble, bass], in the music flow and in a new flow alike
    t:eq(pasteTarget({ 1, 1, 2, 2 }, { false, true, true, true }, { [1] = 2, [2] = 2 }), "1:2")
  end,
  the_player_s_first_voice_when_its_voices_are_not_one_per_staff = function(t)
    -- three voices on two staves: which staff the third is on can't be told, so the paste starts on the first
    t:eq(pasteTarget({ 1, 1, 1, 2 }, { false, false, true, true }, { [1] = 2, [2] = 1 }), "1:1")
  end,
}
