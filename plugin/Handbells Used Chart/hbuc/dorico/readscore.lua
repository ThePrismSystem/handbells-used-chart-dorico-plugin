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

-- Players in score order, named as the dialog lists them (repeats told apart), the name of each instrument, and
-- each player's instrument ids.
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
  local players, nameOf, idsOf = {}, {}, {}
  for i, e in ipairs(kept) do
    players[i] = { key = e.key, name = unique[i] }
    idsOf[i] = {}
    for _, ins in ipairs(e.player.instruments) do
      nameOf[ins.id] = unique[i]
      idsOf[i][#idsOf[i] + 1] = ins.id
    end
  end
  return players, nameOf, idsOf
end

-- A player holding Dorico's Handbells as well as an instrument written at pitch keeps the Handbells convention.
local function allAtPitch(ids, writtenAtPitch)
  for _, id in ipairs(ids) do
    if not writtenAtPitch[id] then return false end
  end
  return #ids > 0
end

-- opts: {log, skipFlowId, skipKeys = {[key] = true}, layoutId (the full score's), tempDir}. Returns
-- {players = {{key, name, atPitch}}, records}. atPitch is true for a player whose instruments are all written at
-- pitch.
function readscore.scan(app, opts)
  local log = opts.log
  local players, nameOf, idsOf = namePlayers(app.currentScore, opts.skipKeys or {})
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
  local saved = #notes > 0 and savedcopy.read(app, log, opts.tempDir) or { notes = {}, writtenAtPitch = {} }
  local records, elsewhere = reading.records(notes, saved.notes, opts.layoutId)
  if elsewhere > 0 then
    log:line(elsewhere .. " note(s) have a notehead or colour set only for another block instance, so they read"
      .. " without it")
  end
  for i, pl in ipairs(players) do pl.atPitch = allAtPitch(idsOf[i], saved.writtenAtPitch) end
  return { players = players, records = records }
end

return readscore
