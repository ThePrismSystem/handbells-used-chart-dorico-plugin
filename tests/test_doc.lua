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

return {
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
