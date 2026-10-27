-- Can the plug-in tell a Handbells instrument (sounds an octave above written) from one written at pitch, such as
-- the fixture's Organ? Looks at everything a note, an instrument and the libraries expose. Read-only.
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])")
local mine = here .. "?.lua;" .. here .. "lib/?.lua"
for name in pairs(package.loaded) do
  if package.searchpath(name, mine) then package.loaded[name] = nil end
end
if not package.path:find(mine, 1, true) then package.path = mine .. ";" .. package.path end
local probe = require("probe")

local function try(obj, key)
  local ok, v = pcall(function() return obj[key] end)
  if not ok then return "error: " .. tostring(v):sub(1, 60) end
  if v == nil then return nil end
  local okS, s = pcall(tostring, v)
  return okS and s:sub(1, 160) or ("<" .. type(v) .. ">")
end

probe.run("33_instrument_type", function(p)
  local app = DoApp.DoApp()
  local score = app.currentScore
  local ctx = DoCore.PropertyContext()
  local flow = score.flows[1]

  -- every property of the first note in each instrument's first voice stream
  local notes = {}
  for i, s in ipairs(flow.voiceStreams) do
    local owner = flow.instruments[i].id
    local ok, list = pcall(function() return s.events end)
    if ok and not notes[owner] then
      for _, e in ipairs(list) do
        local t = tostring(e)
        if t:find("kNoteEvent", 1, true) then
          local props = {}
          for _, n in ipairs(e.propertyTable:getPropertyNames()) do
            local okV, v = pcall(function() return e.propertyTable:get(n, ctx) end)
            local okT, vt = pcall(function() return v.type end)
            props[#props + 1] = n .. "=" .. (okV and tostring(v) or "?") .. (okT and (" (type " .. tostring(vt) .. ")") or "")
          end
          local okP, pws = pcall(function() return tostring(e.pitchWithSpelling) end)
          notes[owner] = { event = t, props = props, pitchWithSpelling = okP and pws or "?" }
          break
        end
      end
    end
  end
  p:fact("notes", notes)

  -- what an instrument and a flow instrument answer to
  local keys = { "id", "entity", "entityID", "entityId", "instrumentEntity", "instrumentEntityID", "type", "family",
    "transposition", "transpositionInterval", "isTransposing", "name", "shortName", "staves", "staveCount",
    "clef", "range", "player" }
  local inst = {}
  for _, pl in ipairs(score.players) do
    local ins = pl.instruments[1]
    local row = { player = tostring(pl) }
    for _, k in ipairs(keys) do row[k] = try(ins, k) end
    inst[#inst + 1] = row
  end
  p:fact("instruments", inst)
  local fis = {}
  for i, fi in ipairs(flow.instruments) do
    local row = {}
    for _, k in ipairs(keys) do row[k] = try(fi, k) end
    fis[i] = row
  end
  p:fact("flowInstruments", fis)

  -- the libraries: which instrument entities the project holds
  local lib = {}
  local okL, libs = pcall(function() return score.libraries end)
  lib.libraries = okL and tostring(libs) or "?"
  if okL and libs then
    for _, which in ipairs({ "defaultLibrary", "userLibrary" }) do
      local okW, l = pcall(function() return libs[which] end)
      lib[which] = okW and tostring(l) or "?"
      if okW and l then
        local okI, instLib = pcall(function() return l.instruments end)
        lib[which .. ".instruments"] = okI and tostring(instLib) or "?"
        if okI and instLib then
          local okItems, items = pcall(function() return instLib.items end)
          local ids = {}
          if okItems and type(items) == "table" then
            for _, it in ipairs(items) do
              ids[#ids + 1] = try(it, "id")
              if #ids >= 12 then break end
            end
            lib[which .. ".count"] = #items
          end
          lib[which .. ".items"] = table.concat(ids, ", ")
          local okF, found = pcall(function() return instLib:find("instrument.pitchedpercussion.handbells") end)
          lib[which .. ".findHandbells"] = okF and tostring(found) or ("error " .. tostring(found):sub(1, 120))
        end
      end
    end
  end
  p:fact("libraries", lib)

  -- the clefs on the staves (ClefEvent knows a transposing and a non-transposing clef)
  local clefs = {}
  for i, s in ipairs(flow.staveStreams) do
    local ok, list = pcall(function() return s.events end)
    if ok then
      for _, e in ipairs(list) do
        local t = tostring(e)
        if t:find("Clef", 1, true) then
          clefs[#clefs + 1] = i .. ": " .. t:sub(1, 80) .. " | nonTransposing " .. tostring(try(e, "nonTransposingClefEntity"))
            .. " | transposing " .. tostring(try(e, "transposingClefEntity"))
        end
      end
    end
  end
  p:fact("clefs", clefs)
end)
