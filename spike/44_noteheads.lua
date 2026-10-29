-- How does a notehead set chosen in Dorico's own UI read from Lua? Read-only, on the active project: for every voice
-- stream whose events Lua can list, each note's property names (tallied), and how kNoteheadSetOverride reads on the
-- notes that list it (its text, Variant type and validity).
--   python tools/dorico/run_lua.py spike/44_noteheads.lua --open PROJECT.dorico
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])")
local repo = here .. "../"
local mine = here .. "lib/?.lua;" .. repo .. "plugin/Handbells Used Chart/?.lua"
for name in pairs(package.loaded) do
  if name:match("^hbuc") or package.searchpath(name, mine) then package.loaded[name] = nil end
end
if not package.path:find(mine, 1, true) then package.path = mine .. ";" .. package.path end
local probe = require("probe")

local function describe(v)
  local okT, t = pcall(function() return v.type end)
  local okV, valid = pcall(function() return v.valid end)
  local okS, s = pcall(function() return v:toString() end)
  local okI, i = pcall(function() return v:toInt() end)
  return tostring(v) .. " (type " .. (okT and tostring(t) or "?") .. ", valid " .. (okV and tostring(valid) or "?")
    .. ", toString " .. (okS and ("'" .. tostring(s) .. "'") or "?") .. ", toInt " .. (okI and tostring(i) or "?") .. ")"
end

probe.run("44_noteheads", function(p)
  local app = DoApp.DoApp()
  local ctx = DoCore.PropertyContext()
  local names, heads, samples, unreadable = {}, {}, {}, {}
  for fi, flow in ipairs(app.currentScore.flows) do
    for si, s in ipairs(flow.voiceStreams) do
      local ok, list = pcall(function() return s.events end)
      if not ok then
        unreadable[#unreadable + 1] = "flow " .. fi .. " stream " .. si
      else
        for _, e in ipairs(list) do
          local text = tostring(e)
          if text:match("^kNoteEvent") or text:match("^kGraceNoteEvent") then
            local listed = e.propertyTable:getPropertyNames()
            local hasHead = false
            for _, n in ipairs(listed) do
              names[n] = (names[n] or 0) + 1
              if n == "kNoteheadSetOverride" then hasHead = true end
            end
            local head = describe(e.propertyTable:get("kNoteheadSetOverride", ctx))
            local k = "flow " .. fi .. ", listed " .. tostring(hasHead) .. ": " .. head
            heads[k] = (heads[k] or 0) + 1
            if hasHead and #samples < 6 then
              local all = {}
              for _, n in ipairs(listed) do all[#all + 1] = n .. "=" .. describe(e.propertyTable:get(n, ctx)) end
              samples[#samples + 1] = text .. " | " .. table.concat(all, "; ")
            end
          end
        end
      end
    end
  end
  p:fact("propertyNames", names)
  p:fact("noteheadReads", heads)
  p:fact("samples", samples)
  p:fact("unreadableStreams", unreadable)
end)
