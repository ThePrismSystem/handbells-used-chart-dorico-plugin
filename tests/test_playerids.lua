-- Player ids from a saved project's score: commands take them and Lua doesn't expose them. Each player's instruments
-- carry their ids, and the plug-in knows a player by its first instrument's id.
local build = require("dtn_build")
local dtn = require("hbuc.dtn")
local playerids = require("hbuc.playerids")
local zip = require("hbuc.zip")

local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./"

local function player(id, ...)
  local instruments = {}
  for i, instrument in ipairs({ ... }) do
    instruments[i] = { "instrument", nil, { { "instrumentID", tostring(instrument) } } }
  end
  return { "scorePlayer", nil, { { "playerID", tostring(id) }, { "baseName", "Player " .. id },
    { "instruments", nil, instruments } } }
end

-- "instrument=player" pairs, sorted, so two maps compare as text
local function listed(map)
  local out = {}
  for k, v in pairs(map) do out[#out + 1] = tostring(k) .. "=" .. tostring(v) end
  table.sort(out)
  return table.concat(out, " ")
end

local function tree(...)
  return dtn.decode(build.tree({ "kScore", nil, { { "scorePlayers", nil, { { "array", nil, { ... } } } } } }))
end

return {
  the_fixture_s_players = function(t)
    local f = assert(io.open(here .. "../fixtures/handbells-fixture.dorico", "rb"))
    local bytes = f:read("*a")
    f:close()
    local ids = playerids.fromTree(dtn.decode(zip.entry(bytes, "score.dtn")))
    t:eq(listed(ids), listed({ [0] = 0, [1] = 1, [2] = 2 }))
  end,
  -- A project whose players 1 and 2 were deleted: Dorico crashed when the plug-in renamed player 1 to find ids.
  ids_left_by_deleted_players_are_skipped = function(t)
    t:eq(listed(playerids.fromTree(tree(player(0, 1), player(3, 5)))), listed({ [1] = 0, [5] = 3 }))
  end,
  -- Steinberg's Smith example lists its players out of id order, with instrument ids that differ from them.
  players_out_of_id_order = function(t)
    local ids = playerids.fromTree(tree(player(0, 6), player(5, 7), player(3, 3)))
    t:eq(listed(ids), listed({ [6] = 0, [7] = 5, [3] = 3 }))
  end,
  every_instrument_of_a_doubling_player_gives_its_id = function(t)
    t:eq(listed(playerids.fromTree(tree(player(4, 6, 9)))), listed({ [6] = 4, [9] = 4 }))
  end,
  a_score_without_players = function(t)
    t:eq(listed(playerids.fromTree(dtn.decode(build.tree({ "kScore", nil, {} })))), listed({}))
  end,
}
