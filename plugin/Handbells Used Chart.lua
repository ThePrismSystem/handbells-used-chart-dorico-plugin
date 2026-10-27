-- Handbells Used Chart for Dorico: draws "handbells used" charts into the full score.
-- Dorico lists this file in the Script menu; the code lives in the folder beside it.
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])")
local root = here .. "Handbells Used Chart/"
local mine = root .. "?.lua"

-- Dorico keeps one Lua state for every script it runs, so modules from an earlier run (or an older install)
-- would otherwise stay loaded.
for name in pairs(package.loaded) do
  if name:match("^hbuc") then package.loaded[name] = nil end
end
if not package.path:find(mine, 1, true) then package.path = mine .. ";" .. package.path end

-- main.run reports its own failures. One that stops the run before it gets that far would otherwise end it without
-- a word to the user, so it is shown here.
local ok, err = pcall(function() require("hbuc.main").run(require("hbuc.dorico.context").real(root)) end)
if not ok then pcall(function() require("hbuc.dorico.context").failed(root, err) end) end
