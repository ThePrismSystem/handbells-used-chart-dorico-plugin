-- Asserts the fixture score has the notes, noteheads and colours heads.json describes.
-- args: headsPath (heads.json), expected ({player = {kind = count}})
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])")
local mine = here .. "?.lua;" .. here .. "lib/?.lua;" .. here .. "../spike/lib/?.lua"
for name in pairs(package.loaded) do -- Dorico keeps one Lua state between runs: reload our modules
  if package.searchpath(name, mine) then package.loaded[name] = nil end
end
if not package.path:find(mine, 1, true) then package.path = mine .. ";" .. package.path end
local probe = require("probe")
local json = require("json")
local fixtureindex = require("fixtureindex")

local function readJson(path)
  local f = assert(io.open(path, "rb"))
  local s = f:read("*a")
  f:close()
  return json.decode(s)
end

local function prop(e, name)
  return tostring(e.propertyTable:get(name, DoCore.PropertyContext()))
end

probe.run("verify_fixture", function(p)
  local app = DoApp.DoApp()
  local flow = app.currentScore.flows[1]
  local heads = readJson(p.args.headsPath)
  local stray = 0
  for _, s in ipairs(flow.voiceStreams) do
    for _, e in ipairs(s.events) do
      if tostring(e):find("HBUC", 1, true) then stray = stray + 1 end
    end
  end
  p:check("no marker texts left in the fixture", stray == 0, stray)
  local index, counts, owners = fixtureindex.build(app, flow)

  local ownerNames = {}
  for id, name in pairs(owners) do ownerNames[#ownerNames + 1] = id .. "=" .. name end
  table.sort(ownerNames)
  p:fact("owners", table.concat(ownerNames, ", "))

  for player, kinds in pairs(p.args.expected) do
    local want = 0
    for _, n in pairs(kinds) do want = want + n end
    p:check("note events for " .. player, counts[player] == want, tostring(counts[player]) .. " of " .. want)
  end

  local missing, wrongHead, wrongColour = {}, {}, {}
  local colourSamples = {}
  for _, h in ipairs(heads) do
    local found = fixtureindex.lookup(index, h)
    local label = h.player .. " bar " .. h.bar .. " " .. h.written .. (h.grace and " (grace)" or "")
    if not found then
      missing[#missing + 1] = label
    else
      local head = prop(found.event, "kNoteheadSetOverride")
      local headOk
      if h.noteheadSet == "noteheadset.default" then headOk = head == "" or head:find("noteheadset.default", 1, true)
      else headOk = head:find(h.noteheadSet, 1, true) ~= nil end
      if not headOk then wrongHead[#wrongHead + 1] = label .. " has '" .. head .. "'" end

      local colour = prop(found.event, "kEventColour")
      local colourOk
      if h.colour ~= json.null and h.colour then
        colourOk = colour:lower():find(h.colour:sub(2):lower(), 1, true) ~= nil
        colourSamples[h.colour] = colour
      else
        colourOk = colour == ""
      end
      if not colourOk then wrongColour[#wrongColour + 1] = label .. " has '" .. colour .. "'" end
    end
  end
  p:check("every heads.json note found", #missing == 0, table.concat(missing, "; "))
  p:check("noteheads as heads.json says", #wrongHead == 0, table.concat(wrongHead, "; "))
  p:check("colours as heads.json says", #wrongColour == 0, table.concat(wrongColour, "; "))
  p:fact("colourValues", colourSamples)

  local graces = 0
  for _, entry in pairs(index) do
    if entry.parsed.kind == "grace" and owners[entry.stream.id] == "Handbells (A)" then graces = graces + 1 end
  end
  p:check("one grace note in Handbells (A)", graces == 1, graces)

  local c4 = index[fixtureindex.key("Handbells (A)", 1, 0, "C", false)]
  if p:check("written C4 found", c4 ~= nil) then
    local pitch = tonumber(prop(c4.event, "kNotePitch"))
    p:fact("pitch_of_written_C4", pitch)
    p:fact("spelling_shown_for_written_C4", c4.parsed.spelling)
    p:check("kNotePitch is written (60) or sounding (72)", pitch == 60 or pitch == 72, pitch)
  end
end)
