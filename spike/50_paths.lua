-- How do Dorico's io.open and lfs take a path with an accent? Dorico names its MusicXML export folder after the
-- project's title, and the file picker answers in UTF-8. Read-only: spike/50_paths.py first makes
-- <run>/Flows from Noël/Noël - Full score - 01 Noël.musicxml. Reports, as byte escapes, the MusicXML files lfs.dir
-- lists in the run folder's "Flows from …" folders, and whether io.open and lfs.attributes find the file by its UTF-8
-- name, by its Windows-1252 name, and by the name lfs.dir gave.
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])")
local repo = here .. "../"
local mine = here .. "lib/?.lua;" .. repo .. "plugin/Handbells Used Chart/?.lua"
for name in pairs(package.loaded) do
  if name:match("^hbuc") or package.searchpath(name, mine) then package.loaded[name] = nil end
end
if not package.path:find(mine, 1, true) then package.path = mine .. ";" .. package.path end
local probe = require("probe")

local function escaped(s)
  return (s:gsub("[\128-\255]", function(c) return string.format("\\%d", c:byte()) end))
end

probe.run("50_paths", function(p)
  local lfs = require("lfs")
  local run = probe.runDir:gsub("\\", "/")
  local listed = {}
  for name in lfs.dir(run) do
    local sub = run .. name .. "/"
    if name:find("Flows from No", 1, true) and lfs.attributes(sub, "mode") == "directory" then
      for file in lfs.dir(sub) do
        if file:lower():match("%.musicxml$") then listed[#listed + 1] = sub .. file end
      end
    end
  end
  p:fact("listed", (function()
    local out = {}
    for i, path in ipairs(listed) do out[i] = escaped(path) end
    return out
  end)())
  local function tryPath(label, path)
    local f = io.open(path, "rb")
    local opened = f ~= nil
    if f then f:close() end
    p:fact(label, { opened = opened, lfs = lfs.attributes(path, "mode"), path = escaped(path) })
  end
  local name = "No%sl - Full score - 01 No%sl.musicxml"
  tryPath("utf8", run .. "Flows from No\195\171l/" .. string.format(name, "\195\171", "\195\171"))
  tryPath("cp1252", run .. "Flows from No\235l/" .. string.format(name, "\235", "\235"))
  if listed[1] then tryPath("asListed", listed[1]) end
end)
