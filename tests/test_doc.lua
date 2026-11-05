-- EventEdit.Select takes the id of the block that holds the event, which Lua reads from the stream's block
-- instances. A project's instance ids can run out of step with its block ids: in one downloaded arrangement,
-- instance 1061 held block 36, so working the id out from the instance id selected nothing.
local doc = require("hbuc.dorico.doc")
local dump = require("hbuc.dump")

local RULE = "------------------------------"

local function lines(list)
  return table.concat(list, "\n") .. "\n"
end

local TWO_BLOCKS = lines({
  RULE,
  "Start block id: 1061 position: 0",
  "0 (0) dur: 1: kNoteEvent (id:7932) at 0, duration 1  E5 (ends 1)",
  "Start block id: 1070 position: 16",
  "16 (16) dur: 1: kNoteEvent (id:8000) at 16, duration 1  C6 (ends 17)",
})

local function stream(text, instances)
  return { id = 52, dump = function() return text end, blockInstances = instances }
end

local INSTANCES = { { id = 1061, block = { id = 36 } }, { id = 1070, block = { id = 40 } } }

-- doc.playerIds for players with these keys (first instrument ids), with the saved copy's ids stubbed. Returns
-- whether it worked, its result and the commands it sent.
local function playerIdsWith(fromCopy, keys)
  local sent, asked = {}, {}
  local saved = { copy = package.loaded["hbuc.dorico.savedcopy"], doc = package.loaded["hbuc.dorico.doc"] }
  package.loaded["hbuc.dorico.savedcopy"] = { playerIds = function(_, _, dir)
    asked.dir = dir
    return fromCopy
  end }
  package.loaded["hbuc.dorico.doc"] = nil
  local players = {}
  for i, k in ipairs(keys) do players[i] = { instruments = { { id = k } } } end
  local app = { currentScore = { players = players }, doCommand = function(_, c) sent[#sent + 1] = c end }
  local ok, ids = pcall(function()
    return require("hbuc.dorico.doc").playerIds(app, { line = function() end }, "t/")
  end)
  package.loaded["hbuc.dorico.savedcopy"], package.loaded["hbuc.dorico.doc"] = saved.copy, saved.doc
  return ok, ids, sent, asked.dir
end

return {
  -- Renaming the id of a deleted player crashed Dorico 6.2.30, so no id is tried: they are read from a saved copy.
  player_ids_are_read_without_renaming_anyone = function(t)
    local ok, ids, sent, dir = playerIdsWith({ [1] = 0, [5] = 3, [9] = 3 }, { 1, 5 })
    t:ok(ok, tostring(ids))
    t:eq(ids[1], 0)
    t:eq(ids[5], 3)
    t:eq(ids[9], nil, "only the players' keys")
    t:eq(#sent, 0, "no command")
    t:eq(dir, "t/", "the copy goes in the temp folder")
  end,
  a_player_missing_from_the_copy_is_an_error = function(t)
    local ok, err = playerIdsWith({ [1] = 0 }, { 1, 7 })
    t:eq(ok, false)
    t:ok(tostring(err):find("player 7", 1, true), tostring(err))
  end,
  block_id_comes_from_the_instance_holding_the_event = function(t)
    t:eq(doc.blockIdOf(stream(TWO_BLOCKS, INSTANCES), 7932), 36)
  end,
  each_event_gets_its_own_instance_s_block = function(t)
    t:eq(doc.blockIdOf(stream(TWO_BLOCKS, INSTANCES), 8000), 40)
  end,
  a_dump_already_parsed_is_used_as_it_is = function(t)
    -- readscore deletes a copy's events one at a time from one dump of the stream
    local s = stream(nil, INSTANCES)
    s.dump = function() error("dumped again") end
    t:eq(doc.blockIdOf(s, 8000, dump.parse(TWO_BLOCKS)), 40)
  end,
  an_event_the_stream_does_not_hold_is_an_error = function(t)
    t:fails(function() doc.blockIdOf(stream(TWO_BLOCKS, INSTANCES), 1) end)
  end,
  an_instance_the_stream_does_not_list_is_an_error = function(t)
    t:fails(function() doc.blockIdOf(stream(TWO_BLOCKS, { { id = 1061, block = { id = 36 } } }), 8000) end)
  end,
}
