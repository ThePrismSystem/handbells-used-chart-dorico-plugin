-- readscore.scan against a fake score: the dumps say which notes exist and whose they are, and the saved copy
-- (hbuc.dorico.savedcopy, stubbed here) gives each one's notehead set and colour by event id.
local RULE = "------------------------------"

-- A voice stream whose dump lists notes {id, spelling} from position 0, in block instance 1010.
local function voice(notes)
  local lines = { RULE, "Start block id: 1010 position: 0" }
  for i, n in ipairs(notes) do
    lines[#lines + 1] = string.format("%d (%d) dur: 1: kNoteEvent (id:%d) at %d, duration 1  %s (ends %d)",
      i - 1, i - 1, n[1], i - 1, n[2], i)
  end
  local text = table.concat(lines, "\n") .. "\n"
  return { dump = function() return text end }
end

local function player(key, name)
  return setmetatable({ instruments = { { id = key } } }, { __tostring = function() return name end })
end

local function entry(property, value, layout, instance)
  return { property = property, value = value, layout = layout or -1, instance = instance or -1 }
end

-- Players 1 ("Handbells") and 2 ("Chart"), flow 0 with Handbells' C5 (101) and D5 (102), and flow 9 (a chart) with
-- Chart's E5 (900). saved: the stub's answer. Returns scan's result (or error), the stub's calls and the commands
-- sent.
local function scan(saved, opts)
  local bells, chart = player(1, "Handbells"), player(2, "Chart")
  local music = { id = 0, players = { bells }, voiceStreams = { voice({ { 101, "C5" }, { 102, "D5" } }) },
    instruments = { { id = 1 } } }
  local chartFlow = { id = 9, players = { chart }, voiceStreams = { voice({ { 900, "E5" } }) },
    instruments = { { id = 2 } } }
  local commands, calls = {}, {}
  local app = { currentScore = { players = { bells, chart }, flows = { music, chartFlow } } }
  function app.doCommand(_, c) commands[#commands + 1] = c end
  local savedStub = package.loaded["hbuc.dorico.savedcopy"]
  package.loaded["hbuc.dorico.savedcopy"] = { read = function(a, _, tempDir)
    calls[#calls + 1] = { app = a, tempDir = tempDir }
    return saved
  end }
  package.loaded["hbuc.dorico.readscore"] = nil
  local args = { log = { line = function() end }, skipFlowId = 9, skipKeys = { [2] = true }, layoutId = 0,
    tempDir = "t/" }
  for k, v in pairs(opts or {}) do args[k] = v end
  local ok, result = pcall(function() return require("hbuc.dorico.readscore").scan(app, args) end)
  package.loaded["hbuc.dorico.savedcopy"] = savedStub
  package.loaded["hbuc.dorico.readscore"] = nil
  return ok, result, calls, commands
end

return {
  heads_and_colours_come_from_the_saved_copy = function(t)
    local ok, result, calls = scan({
      [101] = { entry("kNoteheadSetOverride", "noteheadset.diamondNoteheads"), entry("kEventColour", "#c80000") },
      [102] = {}, [900] = {},
    })
    t:ok(ok, tostring(result))
    t:eq(#calls, 1, "one saved copy")
    t:eq(calls[1].tempDir, "t/", "in the temp folder")
    t:eq(#result.records, 2, "the chart flow's note is left out")
    t:eq(result.records[1].head, "noteheadset.diamondNoteheads")
    t:eq(result.records[1].colour, "#c80000")
    t:eq(result.records[1].instrument, "Handbells")
    t:eq(result.records[2].head, "noteheadset.default")
  end,
  the_chart_player_is_left_out = function(t)
    local _, result = scan({ [101] = {}, [102] = {}, [900] = {} }, { skipFlowId = -1 })
    t:eq(#result.players, 1)
    t:eq(result.players[1].name, "Handbells")
    t:eq(#result.records, 2, "the chart player's note is not read")
  end,
  the_full_score_and_the_notes_instance_decide = function(t)
    local _, result = scan({
      [101] = { entry("kNoteheadSetOverride", "X", 0, 1010), entry("kNoteheadSetOverride", "Y") },
      [102] = { entry("kNoteheadSetOverride", "Z", 0, 1011) }, [900] = {},
    })
    t:eq(result.records[1].head, "X", "layout 0, the note's instance 1010")
    t:eq(result.records[2].head, "noteheadset.default", "another instance's value doesn't apply")
  end,
  the_read_changes_nothing = function(t)
    local _, _, _, commands = scan({ [101] = {}, [102] = {}, [900] = {} })
    t:eq(#commands, 0, "no command at all")
  end,
  no_notes_no_copy = function(t)
    local bells = player(1, "Handbells")
    local app = { currentScore = { players = { bells }, flows = { { id = 0, players = { bells },
      voiceStreams = { voice({}) }, instruments = { { id = 1 } } } } } }
    local called = false
    local savedStub = package.loaded["hbuc.dorico.savedcopy"]
    package.loaded["hbuc.dorico.savedcopy"] = { read = function() called = true return {} end }
    package.loaded["hbuc.dorico.readscore"] = nil
    local result = require("hbuc.dorico.readscore").scan(app, { log = { line = function() end }, layoutId = 0,
      tempDir = "t/" })
    package.loaded["hbuc.dorico.savedcopy"] = savedStub
    package.loaded["hbuc.dorico.readscore"] = nil
    t:eq(#result.records, 0)
    t:ok(not called, "nothing to read, so no copy")
  end,
  a_note_missing_from_the_copy_fails = function(t)
    local ok, err = scan({ [101] = {} })
    t:ok(not ok, "fails")
    t:ok(tostring(err):find("note 102 is not in the saved copy", 1, true), tostring(err))
  end,
}
