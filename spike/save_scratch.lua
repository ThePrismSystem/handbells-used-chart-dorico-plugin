-- Save the scratch copy over itself (after probe.run has confirmed the active project is that copy), so a
-- project from an older Dorico can be reused as a test input that opens without the "earlier version" notice.
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])")
local mine = here .. "?.lua;" .. here .. "lib/?.lua"
for name in pairs(package.loaded) do
  if package.searchpath(name, mine) then package.loaded[name] = nil end
end
if not package.path:find(mine, 1, true) then package.path = mine .. ";" .. package.path end
local probe = require("probe")

probe.run("save_scratch", function(p)
  if not p.facts.scratchVerified then error("refusing to save: the scratch copy was not verified") end
  DoApp.DoApp():doCommand("File.Save")
  p:check("saved", true)
end)
