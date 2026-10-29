-- Can a notehead set Lua can't read still be told apart and named? On a scratch copy whose first flow Lua can list
-- (a hand-made chart flow), in two runs:
--   args.step = "set": picks two notes that already list kNoteheadSetOverride (set in Dorico's UI) and four that
--     don't, then gives the plain ones a notehead set four ways: by UI.InvokePropertyChangeValue (diamond), by
--     Edit.SetNoteheadSetOverride (diamond, then X) and from Lua (diamond). Reports the ids it used.
--   args.step = "compare", args.ids = {name = eventId}: how each note's kNoteheadSetOverride reads, and which of
--     those Variants compare equal (__eq).
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

local function listsHead(e)
  for _, n in ipairs(e.propertyTable:getPropertyNames()) do
    if n == "kNoteheadSetOverride" then return true end
  end
  return false
end

probe.run("45_head_compare", function(p)
  local cases = require("cases")
  local commands = require("hbuc.commands")
  local doc = require("hbuc.dorico.doc")
  local ctx = cases.context(p)
  local app = ctx.app
  local pctx = DoCore.PropertyContext()
  local flow = app.currentScore.flows[1]

  -- every note of the flow with its stream
  local notes = {}
  for _, s in ipairs(flow.voiceStreams) do
    for _, e in ipairs(s.events) do
      if tostring(e):match("^kNoteEvent") then notes[#notes + 1] = { e = e, s = s } end
    end
  end
  local byId = {}
  for _, n in ipairs(notes) do byId[n.e.id] = n end

  if p.args.step == "set" then
    local ids, plain = {}, {}
    for _, n in ipairs(notes) do
      if listsHead(n.e) then
        if not ids.chimeA then ids.chimeA = n.e.id elseif not ids.chimeB then ids.chimeB = n.e.id end
      else
        plain[#plain + 1] = n
      end
    end
    ids.byProperty, ids.byCommandDiamond, ids.byCommandX = plain[1].e.id, plain[2].e.id, plain[3].e.id
    ids.byLua, ids.untouched = plain[4].e.id, plain[5].e.id
    local function sel(id) doc.select(app, ctx.log, flow.id, id, doc.blockIdOf(byId[id].s, id)) end
    sel(ids.byProperty)
    doc.command(app, ctx.log, commands.build("UI.InvokePropertyChangeValue",
      { { "Type", "kNoteheadSetOverride" }, { "Value", "noteheadset.diamondNoteheads" } }))
    sel(ids.byCommandDiamond)
    doc.command(app, ctx.log, commands.build("Edit.SetNoteheadSetOverride",
      { { "NoteheadSetEntityID", "noteheadset.diamondNoteheads" } }))
    sel(ids.byCommandX)
    doc.command(app, ctx.log, commands.build("Edit.SetNoteheadSetOverride",
      { { "NoteheadSetEntityID", "noteheadset.Xnoteheads" } }))
    doc.command(app, ctx.log, "Edit.SelectNone")
    p:fact("setByLua", tostring(byId[ids.byLua].e.propertyTable:set("kNoteheadSetOverride",
      DoCore.Variant.createString("noteheadset.diamondNoteheads"), pctx)))
    local spelled = {}
    for k, id in pairs(ids) do spelled[k] = tostring(byId[id].e) end
    p:fact("ids", ids)
    p:fact("notes", spelled)
    return
  end

  local ids = p.args.ids
  local names, values, reads = {}, {}, {}
  for k in pairs(ids) do names[#names + 1] = k end
  table.sort(names)
  for _, k in ipairs(names) do
    local n = byId[ids[k]]
    if not n then error("no note " .. tostring(ids[k]) .. " for " .. k) end
    values[k] = n.e.propertyTable:get("kNoteheadSetOverride", pctx)
    reads[k] = "listed " .. tostring(listsHead(n.e)) .. ": " .. describe(values[k]) .. " | " .. tostring(n.e)
  end
  local equal = {}
  for i, a in ipairs(names) do
    for j = i + 1, #names do
      local b = names[j]
      local ok, same = pcall(function() return values[a] == values[b] end)
      equal[#equal + 1] = a .. " == " .. b .. ": " .. (ok and tostring(same) or ("error " .. tostring(same)))
    end
  end
  p:fact("reads", reads)
  p:fact("equal", equal)
end)
