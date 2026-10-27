-- Small helpers over Dorico's object model and commands, shared by the adapters. Only calls the probes in spike/
-- proved are used here.
local commands = require("hbuc.commands")
local dump = require("hbuc.dump")
local files = require("hbuc.dorico.files")

local doc = {}

function doc.flowById(score, id)
  for _, f in ipairs(score.flows) do
    if f.id == id then return f end
  end
  return nil
end

-- The position (from 1) of a flow in score order, which is the text export's FlowNumber.
function doc.flowNumber(score, id)
  for i, f in ipairs(score.flows) do
    if f.id == id then return i end
  end
  return nil
end

-- Players have no id and no __eq; their first instrument's id is unique, and equals the player id commands take.
function doc.playerKey(player)
  return player.instruments[1].id
end

function doc.playerByKey(score, key)
  for _, p in ipairs(score.players) do
    if doc.playerKey(p) == key then return p end
  end
  return nil
end

function doc.flowKeys(flow)
  local keys = {}
  for _, p in ipairs(flow.players) do keys[#keys + 1] = doc.playerKey(p) end
  return keys
end

function doc.dumpOf(stream)
  return dump.parse(stream:dump())
end

-- {{stream, key}} for every voice stream: flow.instruments has one entry per voice stream, in the same order,
-- carrying the owning instrument's id.
function doc.voiceOwners(flow)
  local streams, owners = flow.voiceStreams, flow.instruments
  if #owners ~= #streams then
    error("unexpected stream layout in flow " .. tostring(flow.id) .. ": " .. #streams .. " voice streams, "
      .. #owners .. " instrument entries")
  end
  local out = {}
  for i, s in ipairs(streams) do out[i] = { stream = s, key = owners[i].id } end
  return out
end

function doc.command(app, log, text)
  log:line("command", text)
  app:doCommand(text)
end

function doc.select(app, log, flowId, eventId, blockId)
  doc.command(app, log, "Edit.SelectNone")
  doc.command(app, log, commands.select(flowId, eventId, blockId))
end

-- The text export as CSV text. Dorico writes <name>.csv beside the <name>.txt it is asked for.
function doc.exportText(app, log, tempDir, name)
  local base = tempDir .. name
  os.remove(base .. ".csv")
  doc.command(app, log, commands.build("File.Export.Text", { { "File", base .. ".txt" }, { "Show", "false" } }))
  local csv = files.read(base .. ".csv")
  if not csv then error("File.Export.Text wrote no " .. base .. ".csv") end
  return csv
end

-- {[key] = player id} for every player. Lua has no player ids, and in a project whose players and instruments
-- were not made one for one (Steinberg's own Smith example, for one) they differ from the instrument ids the
-- plug-in uses as keys. Each candidate id in turn is renamed to a unique token; the player that takes it is noted
-- and given its exact name back (Name only, so its short name is untouched).
function doc.playerIds(app, log)
  local names = {}
  for _, pl in ipairs(app.currentScore.players) do names[doc.playerKey(pl)] = tostring(pl) end
  local want, found, ids = 0, 0, {}
  for _ in pairs(names) do want = want + 1 end
  for id = 0, 8 * want + 64 do
    if found == want then break end
    local token = "HBUCID" .. id
    doc.command(app, log, commands.renamePlayerName(id, token))
    for _, pl in ipairs(app.currentScore.players) do
      if tostring(pl) == token then
        local key = doc.playerKey(pl)
        ids[key] = id
        found = found + 1
        doc.command(app, log, commands.renamePlayerName(id, names[key]))
        if tostring(doc.playerByKey(app.currentScore, key)) ~= names[key] then
          error("a player's name could not be put back: " .. names[key])
        end
      end
    end
  end
  if found < want then error("the ids of " .. (want - found) .. " player(s) could not be found") end
  return ids
end

function doc.layouts(score)
  local out = {}
  for _, l in ipairs(score.layouts) do
    local keys = {}
    for _, p in ipairs(l.players) do keys[#keys + 1] = doc.playerKey(p) end
    out[#out + 1] = { id = l.id, keys = keys }
  end
  return out
end

function doc.setString(event, property, value)
  local ok = event.propertyTable:set(property, DoCore.Variant.createString(value), DoCore.PropertyContext())
  if not ok then error("Dorico did not set " .. property .. " on event " .. tostring(event.id)) end
end

function doc.setTrue(event, property)
  doc.setString(event, property, "true")
end

function doc.getString(event, property)
  return tostring(event.propertyTable:get(property, DoCore.PropertyContext()))
end

return doc
