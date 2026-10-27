-- On a voice stream whose .events throws "Not implemented" (lyrics, slurs, techniques...), do its block
-- instances' .events or .block.events still list the notes, with property tables? Read-only.
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])")
local mine = here .. "?.lua;" .. here .. "lib/?.lua"
for name in pairs(package.loaded) do
  if package.searchpath(name, mine) then package.loaded[name] = nil end
end
if not package.path:find(mine, 1, true) then package.path = mine .. ";" .. package.path end
local probe = require("probe")

local function tryList(fn)
  local ok, list = pcall(fn)
  if not ok then return { ok = false, err = tostring(list):sub(1, 90) } end
  local n, notes, firstHead = 0, 0, nil
  local ctx = DoCore.PropertyContext()
  for _, e in ipairs(list) do
    n = n + 1
    local okT, t = pcall(tostring, e)
    if okT and t:find("kNoteEvent", 1, true) then
      notes = notes + 1
      if not firstHead then
        local okH, h = pcall(function() return tostring(e.propertyTable:get("kNoteheadSetOverride", ctx)) end)
        local okP, pw = pcall(function() return tostring(e.pitchWithSpelling) end)
        firstHead = (okH and h or "?") .. " / " .. (okP and pw or "?")
      end
    end
  end
  return { ok = true, events = n, notes = notes, firstHead = firstHead }
end

probe.run("18_block_events", function(p)
  local app = DoApp.DoApp()
  local flow = app.currentScore.flows[1]
  local rows = {}
  for _, s in ipairs(flow.voiceStreams) do
    local row = { stream = s.id, direct = tryList(function() return s.events end) }
    local okB, bis = pcall(function() return s.blockInstances end)
    row.blockInstances = okB and #bis or ("error: " .. tostring(bis):sub(1, 90))
    if okB then
      row.instances = {}
      for i, bi in ipairs(bis) do
        if i > 3 then break end
        row.instances[#row.instances + 1] = {
          position = (function() local o, v = pcall(function() return tostring(bi.position) end) return o and v or "?" end)(),
          viaInstance = tryList(function() return bi.events end),
          viaBlock = tryList(function() return bi.block.events end),
        }
      end
    end
    local okD, d = pcall(function() return s:dump() end)
    local dumpNotes = 0
    if okD then for _ in d:gmatch(": kNoteEvent %(id:") do dumpNotes = dumpNotes + 1 end end
    row.dumpNotes = dumpNotes
    rows[#rows + 1] = row
  end
  p:fact("rows", rows)
end)
