-- Index the fixture's note events by the keys heads.json uses: player|bar|pos|name|grace.
local events = require("events")
local streammap = require("streammap")

local fixtureindex = {}

local BEATS_PER_BAR = 4

function fixtureindex.key(player, bar, pos, name, grace)
  return table.concat({ player, bar, pos, name, grace and "g" or "n" }, "|")
end

-- heads.json names a note by player, bar, position and spelling, not by voice: two voices with the same note there
-- would share one key, and one would silently take the other's head. Refused, so the fixture is changed instead.
function fixtureindex.add(index, key, entry)
  if index[key] then error("two notes share the key " .. key .. ": heads.json cannot tell them apart") end
  index[key] = entry
end

-- Returns index {[key] = {event=, parsed=, stream=}}, counts {[player] = n}, owners {[streamId] = player}.
function fixtureindex.build(app, flow)
  local owners = streammap.owners(app, flow)
  local index, counts = {}, {}
  for _, s in ipairs(flow.voiceStreams) do
    local player = owners[s.id]
    if player then
      for _, e in ipairs(s.events) do
        local ev = events.parse(tostring(e))
        if ev.kind == "note" or ev.kind == "grace" then
          local bar = math.floor(ev.pos / BEATS_PER_BAR) + 1
          local pos = ev.pos - BEATS_PER_BAR * (bar - 1)
          fixtureindex.add(index, fixtureindex.key(player, bar, pos, ev.name, ev.kind == "grace"),
            { event = e, parsed = ev, stream = s })
          counts[player] = (counts[player] or 0) + 1
        end
      end
    end
  end
  return index, counts, owners
end

function fixtureindex.lookup(index, head)
  return index[fixtureindex.key(head.player, head.bar, head.pos, head.name, head.grace)]
end

return fixtureindex
