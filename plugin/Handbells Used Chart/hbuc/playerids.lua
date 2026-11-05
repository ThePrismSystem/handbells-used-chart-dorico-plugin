-- Player ids from a saved project's score (hbuc.dtn). Commands and layout options take player ids, which Lua doesn't
-- expose, and the plug-in knows a player by its first instrument's id. They can't be found by trying ids in turn:
-- Dorico 6.2.30 crashed when Project.Player.Rename was given the id of a deleted player.
local dtn = require("hbuc.dtn")

local playerids = {}

-- {[instrument id] = player id} for every instrument of every player.
function playerids.fromTree(tree)
  local ids = {}
  local players = dtn.child(tree, 0, "scorePlayers")
  local list = players and dtn.child(tree, players, "array")
  for _, player in ipairs(list and dtn.children(tree, list) or {}) do
    local idNode, instruments = dtn.child(tree, player, "playerID"), dtn.child(tree, player, "instruments")
    local id = idNode and tonumber(dtn.value(tree, idNode))
    for _, instrument in ipairs(id and instruments and dtn.children(tree, instruments) or {}) do
      local key = dtn.child(tree, instrument, "instrumentID")
      if key then ids[tonumber(dtn.value(tree, key))] = id end
    end
  end
  return ids
end

return playerids
