-- Can stream:copyRange(from, to, dest, destPos, n) copy a voice stream whose .events throws into a scratch
-- stream that .events can read? Tries several values of the int argument. Works in a new flow of a scratch
-- copy only.
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])")
local mine = here .. "?.lua;" .. here .. "lib/?.lua"
for name in pairs(package.loaded) do
  if package.searchpath(name, mine) then package.loaded[name] = nil end
end
if not package.path:find(mine, 1, true) then package.path = mine .. ";" .. package.path end
local probe = require("probe")

local RL = function(n) return DoCore.RhythmicLength(n) end

local function dumpKinds(s)
  local ok, d = pcall(function() return s:dump() end)
  local seen = {}
  if ok then for k in d:gmatch(": (k%a+) %(id:") do seen[k] = (seen[k] or 0) + 1 end end
  local parts = {}
  for k, n in pairs(seen) do parts[#parts + 1] = k .. "=" .. n end
  table.sort(parts)
  return table.concat(parts, ","), seen
end

local function readable(s)
  local ok, list = pcall(function() return s.events end)
  if not ok then return "events throws" end
  local notes = 0
  for _, e in ipairs(list) do
    local okT, t = pcall(tostring, e)
    if okT and t:find("kNoteEvent", 1, true) then notes = notes + 1 end
  end
  return "readable, " .. #list .. " events, " .. notes .. " notes"
end

probe.run("21_copyrange", function(p)
  local app = DoApp.DoApp()
  local score = app.currentScore
  local music = score.flows[1]
  local source
  for _, s in ipairs(music.voiceStreams) do
    local okE = pcall(function() return s.events end)
    if not okE and not source then source = s end
  end
  if not p:check("found a voice stream whose events throw", source ~= nil) then return end
  local srcKinds, srcSeen = dumpKinds(source)
  p:fact("sourceKinds", srcKinds)
  local before = {}
  for _, f in ipairs(score.flows) do before[f.id] = true end
  app:doCommand("Project.Flow.New")
  local scratch
  for _, f in ipairs(app.currentScore.flows) do if not before[f.id] then scratch = f end end
  if not p:check("new flow", scratch ~= nil) then return end
  p:fact("scratchVoices", #scratch.voiceStreams)
  local okD, d = pcall(function() return source:dump() end)
  local last = 0
  if okD then for e in d:gmatch("%(ends ([%d/]+)%)") do
    local a, b = e:match("^(%d+)/(%d+)$")
    local v = a and tonumber(a) / tonumber(b) or tonumber(e)
    if v and v > last then last = v end
  end end
  p:fact("sourceEnd", last)
  local function flowById(id) for _, f in ipairs(app.currentScore.flows) do if f.id == id then return f end end end
  local results = {}
  local targets = {
    { "new flow, exact range", function() return flowById(scratch.id).voiceStreams[1] end, 0 },
    { "new flow, exact range, n=1", function() return flowById(scratch.id).voiceStreams[1] end, 1 },
  }
  for _, s2 in ipairs(music.voiceStreams) do
    if s2.id ~= source.id and pcall(function() return s2.events end) then
      local sid = s2.id
      targets[#targets + 1] = { "same flow stream " .. sid .. ", after the end", function()
        for _, x in ipairs(flowById(music.id).voiceStreams) do if x.id == sid then return x end end end, 0, last + 8 }
      break
    end
  end
  for _, t in ipairs(targets) do
    local dest = t[2]()
    local at = t[4] or 0
    if not t[4] then pcall(function() dest:deleteEventsInRange(RL(0), RL(last + 100)) end) end
    local beforeKinds, beforeSeen = dumpKinds(dest)
    local ok, err = pcall(function() source:copyRange(RL(0), RL(last), dest, RL(at), t[3]) end)
    dest = t[2]()
    local kinds, seen = dumpKinds(dest)
    results[#results + 1] = { target = t[1], ok = ok, err = ok and "" or tostring(err):sub(1, 200), before = beforeKinds,
      kinds = kinds, notesNow = seen.kNoteEvent or 0, notesBefore = beforeSeen.kNoteEvent or 0,
      notesInSource = srcSeen.kNoteEvent or 0, read = readable(dest) }
  end
  p:fact("results", results)
end)
