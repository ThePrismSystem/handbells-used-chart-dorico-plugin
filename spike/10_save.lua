-- Tell a never-saved project from a saved one, and check File.Save is silent on a saved one.
-- args.expectSaved: true for a project opened from a .dorico file, false for a fresh MusicXML import.
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])")
local mine = here .. "?.lua;" .. here .. "lib/?.lua;" .. here .. "../spike/lib/?.lua"
for name in pairs(package.loaded) do -- Dorico keeps one Lua state between runs: reload our modules
  if package.searchpath(name, mine) then package.loaded[name] = nil end
end
if not package.path:find(mine, 1, true) then package.path = mine .. ";" .. package.path end
local probe = require("probe")

-- The text export's first data row carries the project's file path, or "" if it was never saved.
local function projectPath(app)
  local base = os.getenv("TEMP"):gsub("\\", "/") .. "/hbuc-run/save-probe"
  os.remove(base .. ".csv")
  app:doCommand("File.Export.Text?File=" .. base .. ".txt&Show=false")
  local f = assert(io.open(base .. ".csv", "rb"))
  f:read("*l") -- header
  local row = f:read("*l") or ""
  f:close()
  return row:match('^"([^"]*)"') or ""
end

probe.run("10_save", function(p)
  local app = DoApp.DoApp()
  local okL, lfs = pcall(require, "lfs")
  p:fact("lfsAvailable", okL)
  local path = projectPath(app)
  p:fact("projectPath", path)
  p:check("path presence matches expectSaved", (path ~= "") == (p.args.expectSaved == true), path)
  if path == "" or not okL then return end
  local runDir = (os.getenv("TEMP") .. "/hbuc-run/"):gsub("\\", "/"):lower()
  if not p:check("only saves a scratch copy in the run folder", path:gsub("\\", "/"):lower():sub(1, #runDir) == runDir, path) then
    return
  end
  local before = lfs.attributes(path, "modification")
  local t0 = os.time()
  app:doCommand("File.Save")
  local after = lfs.attributes(path, "modification")
  p:fact("saveSeconds", os.time() - t0)
  p:fact("mtimeBefore", before)
  p:fact("mtimeAfter", after)
  p:check("File.Save rewrote the file without blocking", after and before and after > before or after ~= before)
end)
