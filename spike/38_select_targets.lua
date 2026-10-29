-- Targets for spike/38_select_rules.py: the first note or rest of every voice stream, with the stream's id, the
-- block instance its dump names, and each block instance's block id. Also a note in a flow made by this run.
-- Scratch copy only; left open for the driver, which closes it unsaved.
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])")
local repo = here .. "../"
local mine = here .. "?.lua;" .. here .. "lib/?.lua;" .. repo .. "plugin/Handbells Used Chart/?.lua"
for name in pairs(package.loaded) do
  if name:match("^hbuc") or package.searchpath(name, mine) then package.loaded[name] = nil end
end
if not package.path:find(mine, 1, true) then package.path = mine .. ";" .. package.path end
local probe = require("probe")

-- The first event of a parsed dump that a selection can start from (a note, grace note or rest), and its block
-- instance.
local function firstEvent(parsed)
  for _, ev in ipairs(parsed.events) do
    if ev.kind == "note" or ev.kind == "grace" or ev.kind == "rest" then return ev.id, ev.instance end
  end
  return nil
end

probe.run("38_select_targets", function(p)
  local doc = require("hbuc.dorico.doc")
  local app = DoApp.DoApp()
  local targets = {}
  local function add(flow, s, label)
    local first, instance = firstEvent(doc.dumpOf(s))
    if first then
      local instances = {}
      for _, bi in ipairs(s.blockInstances) do
        instances[#instances + 1] = { instanceId = bi.id, blockId = bi.block.id }
      end
      targets[#targets + 1] = { label = label, flowId = flow.id, streamId = s.id, instance = instance,
        eventId = first, instances = instances }
    end
  end
  local existing = {}
  for _, f in ipairs(app.currentScore.flows) do
    existing[f.id] = true
    for i, s in ipairs(f.voiceStreams) do add(f, s, "voice " .. i) end
  end
  app:doCommand("Project.Flow.New")
  for _, f in ipairs(app.currentScore.flows) do
    if not existing[f.id] then
      f.voiceStreams[1]:createNote(DoCore.RhythmicLength(0), DoCore.RhythmicLength(1),
        DoCore.MIDIPitchWithSpelling.fromString("C5"))
      add(f, doc.flowById(app.currentScore, f.id).voiceStreams[1], "new flow")
    end
  end
  p:fact("targets", targets)
end)
