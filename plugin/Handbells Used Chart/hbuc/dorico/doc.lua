-- Small helpers over Dorico's object model and commands, shared by the adapters. Only calls the probes in spike/
-- proved are used here.
local commands = require("hbuc.commands")
local dump = require("hbuc.dump")
local files = require("hbuc.dorico.files")
local savedcopy = require("hbuc.dorico.savedcopy")

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

-- Players have no id and no __eq; their first instrument's id is unique. Commands take player ids (doc.playerIds).
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

-- The EventBlockID that EventEdit.Select takes for one of a stream's events: the id of the block whose instance
-- holds it. It can't be worked out from the instance id: in a downloaded project instance 1061 held block 36, and
-- a select given the wrong block selects nothing, without an error. parsed: the stream's dump, if already parsed.
function doc.blockIdOf(stream, eventId, parsed)
  parsed = parsed or doc.dumpOf(stream)
  local instance
  for _, ev in ipairs(parsed.events) do
    if ev.id == eventId then instance = ev.instance break end
  end
  if not instance then error("event " .. tostring(eventId) .. " is not in stream " .. tostring(stream.id)) end
  for _, bi in ipairs(stream.blockInstances) do
    if bi.id == instance then return bi.block.id end
  end
  error("stream " .. tostring(stream.id) .. " lists no block instance " .. instance)
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
-- plug-in uses as keys. They are read from a copy of the project saved into tempDir.
function doc.playerIds(app, log, tempDir)
  local fromCopy = savedcopy.playerIds(app, log, tempDir)
  local ids = {}
  for _, pl in ipairs(app.currentScore.players) do
    local key = doc.playerKey(pl)
    if fromCopy[key] == nil then error("the saved copy has no id for player " .. tostring(key)) end
    ids[key] = fromCopy[key]
  end
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
