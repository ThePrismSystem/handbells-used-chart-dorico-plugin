-- Reads the players and every note of the music, with noteheads and colours, without changing anything.
-- docs/dorico-lua-guide.md, section 3:
--   * stream:dump() lists every note with its id, block instance and sounding spelling, whatever else the stream
--     holds (stream.events throws on lyrics, slurs, playing techniques and the like);
--   * flow.instruments says which instrument owns each voice stream;
--   * a copy of the project saved into the temp folder holds every note's notehead set and colour, including the
--     ones set in Dorico itself, which propertyTable:get can't read (hbuc.dorico.savedcopy).
local dump = require("hbuc.dump")
local instruments = require("hbuc.instruments")
local reading = require("hbuc.reading")
local doc = require("hbuc.dorico.doc")
local savedcopy = require("hbuc.dorico.savedcopy")

local readscore = {}

-- Players in score order, named as the dialog lists them (repeats told apart), and the name of each instrument.
local function namePlayers(score, skipKeys)
  local kept, names = {}, {}
  for _, pl in ipairs(score.players) do
    local key = doc.playerKey(pl)
    if not skipKeys[key] then
      kept[#kept + 1] = { player = pl, key = key }
      names[#names + 1] = tostring(pl)
    end
  end
  local unique = instruments.unique(names)
  local players, nameOf = {}, {}
  for i, e in ipairs(kept) do
    players[i] = { key = e.key, name = unique[i] }
    for _, ins in ipairs(e.player.instruments) do nameOf[ins.id] = unique[i] end
  end
  return players, nameOf
end

-- opts: {log, skipFlowId, skipKeys = {[key] = true}, layoutId (the full score's), tempDir}. Returns
-- {players = {{key, name}}, records}.
function readscore.scan(app, opts)
  local log = opts.log
  local players, nameOf = namePlayers(app.currentScore, opts.skipKeys or {})
  local notes = {}
  for _, flow in ipairs(app.currentScore.flows) do
    if flow.id ~= opts.skipFlowId then
      local before = #notes
      for _, o in ipairs(doc.voiceOwners(flow)) do
        local name = nameOf[o.key]
        if name then
          for _, n in ipairs(dump.notes(doc.dumpOf(o.stream))) do
            n.instrument = name
            notes[#notes + 1] = n
          end
        end
      end
      log:line("flow", flow.id, #notes - before, "notes")
    end
  end
  local saved = #notes > 0 and savedcopy.read(app, log, opts.tempDir) or {}
  return { players = players, records = reading.records(notes, saved, opts.layoutId) }
end

return readscore
