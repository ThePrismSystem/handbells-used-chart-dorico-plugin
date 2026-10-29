-- Other ways to read a notehead set chosen by command. On a scratch copy of the fixture, driven by
-- spike/51_properties.py:
--   step "setup": sets args.heads[i] (by Edit.SetNoteheadSetOverride, as Dorico's UI does) on flow 1's first notes,
--     reports how Lua reads them, and the overload lists of the property calls (a bound call given seven table
--     arguments fails with "No matching overload found, candidates: ..." and changes nothing).
--   step "select": selects args.eventId (in args.flowId, block args.blockId) and nothing else.
--   step "contexts": reads args.eventId's kNoteheadSetOverride through each PropertyContext the overloads allow.
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])")
local repo = here .. "../"
local mine = here .. "lib/?.lua;" .. repo .. "tests/dorico/lib/?.lua;" .. repo .. "plugin/Handbells Used Chart/?.lua"
for name in pairs(package.loaded) do
  if name:match("^hbuc") or package.searchpath(name, mine) then package.loaded[name] = nil end
end
if not package.path:find(mine, 1, true) then package.path = mine .. ";" .. package.path end
local probe = require("probe")

local function describe(v)
  local okT, t = pcall(function() return v.type end)
  local okV, valid = pcall(function() return v.valid end)
  return tostring(v) .. " (type " .. (okT and tostring(t) or "?") .. ", valid " .. (okV and tostring(valid) or "?") .. ")"
end

local function candidates(fn, ...)
  local ok, err = pcall(fn, ...)
  if ok then return "accepted" end
  return (tostring(err):gsub("No matching overload found, candidates:\n", ""))
end

local function noteById(stream, id)
  for _, e in ipairs(stream.events) do
    if e.id == id then return e end
  end
end

probe.run("51_properties", function(p)
  local cases = require("cases")
  local commands = require("hbuc.commands")
  local doc = require("hbuc.dorico.doc")
  local ctx = cases.context(p)
  local app, log = ctx.app, ctx.log
  local score = app.currentScore
  local pctx = DoCore.PropertyContext()

  if p.args.step == "select" then
    doc.select(app, log, p.args.flowId, p.args.eventId, p.args.blockId)
    p:fact("selected", p.args.eventId)
    return
  end

  if p.args.step == "saveas" then
    doc.command(app, log, commands.build("File.SaveAs", { { "File", p.args.file } }))
    p:fact("saved", p.args.file)
    return
  end

  if p.args.step == "contexts" then
    local flow = doc.flowById(score, p.args.flowId)
    local stream
    for _, s in ipairs(flow.voiceStreams) do
      if s.id == p.args.streamId then stream = s end
    end
    local e = noteById(stream, p.args.eventId)
    local pt = e.propertyTable
    local out = {}
    for _, name in ipairs(pt:getPropertyNames()) do
      out[name] = describe(pt:get(name, pctx))
    end
    p:fact("defaultContext", out)
    for i, build in ipairs(p.args.contexts or {}) do
      local okC, c = pcall(load("return " .. build))
      if okC then
        local okG, v = pcall(function() return pt:get("kNoteheadSetOverride", c) end)
        out = okG and describe(v) or ("get failed: " .. tostring(v))
      else
        out = "context failed: " .. tostring(c)
      end
      p:fact("context" .. i, build .. " -> " .. out)
    end
    return
  end

  -- setup
  local flow = score.flows[1]
  local owners = doc.voiceOwners(flow)
  local stream = owners[1].stream
  local notes = {}
  for _, e in ipairs(stream.events) do
    if tostring(e):match("^kNoteEvent") then notes[#notes + 1] = e end
  end
  local parsed = doc.dumpOf(stream)
  local set = {}
  for i, id in ipairs(p.args.heads) do
    local e = notes[i]
    local blockId = doc.blockIdOf(stream, e.id, parsed)
    doc.select(app, log, flow.id, e.id, blockId)
    doc.command(app, log, commands.build("Edit.SetNoteheadSetOverride", { { "NoteheadSetEntityID", id } }))
    set[i] = { head = id, eventId = e.id, blockId = blockId, text = tostring(e) }
  end
  for i, s in ipairs(set) do
    s.read = describe(noteById(stream, s.eventId).propertyTable:get("kNoteheadSetOverride", pctx))
    set[i] = s
  end
  p:fact("flowId", flow.id)
  p:fact("streamId", stream.id)
  p:fact("set", set)
  doc.select(app, log, flow.id, set[1].eventId, set[1].blockId)

  local pt = notes[1].propertyTable
  local T = { {}, {}, {}, {}, {}, {}, {} }
  local sigs = {}
  sigs["PropertyContext.__init"] = candidates(function() return DoCore.PropertyContext(unpack(T)) end)
  sigs["EventPropertyEntry.__init"] = candidates(function() return DoCore.EventPropertyEntry(unpack(T)) end)
  sigs["Variant.__init"] = candidates(function() return DoCore.Variant(unpack(T)) end)
  sigs["propertyTable.get"] = candidates(function() return pt.get(pt, unpack(T)) end)
  sigs["propertyTable.set"] = candidates(function() return pt.set(pt, unpack(T)) end)
  sigs["propertyTable.getPropertyNames"] = candidates(function() return pt.getPropertyNames(pt, unpack(T)) end)
  local okE, entry = pcall(function() return DoCore.EventPropertyEntry() end)
  if okE then
    for _, m in ipairs({ "context", "name", "value" }) do
      local okM, v = pcall(function() return entry[m] end)
      sigs["EventPropertyEntry()." .. m] = okM and tostring(v) or ("error: " .. tostring(v))
    end
  else
    sigs["EventPropertyEntry()"] = tostring(entry)
  end
  local okL, libs = pcall(function() return score.libraries end)
  sigs["score.libraries"] = okL and tostring(libs) or tostring(libs)
  local okT, tables = pcall(function() return flow.elementTables end)
  if okT then
    sigs["flow.elementTables"] = tostring(tables) .. " #" .. tostring(#tables)
  else
    sigs["flow.elementTables"] = tostring(tables)
  end
  p:fact("signatures", sigs)
end)
