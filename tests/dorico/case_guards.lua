-- The run's guards, on a scratch copy: a never-saved import is refused with notSaved; a saved project passes.
--   args.expect: "notSaved" or "ok"
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])")
local repo = here .. "../../"
local mine = here .. "lib/?.lua;" .. repo .. "spike/lib/?.lua;" .. repo .. "plugin/Handbells Used Chart/?.lua"
for name in pairs(package.loaded) do
  if name:match("^hbuc") or package.searchpath(name, mine) then package.loaded[name] = nil end
end
if not package.path:find(mine, 1, true) then package.path = mine .. ";" .. package.path end
local probe = require("probe")

probe.run("case_guards", function(p)
  -- required here, not above: a module that fails to load is then reported, and the copy closed
  local cases = require("cases")
  local constants = require("hbuc.constants")
  local main = require("hbuc.main")
  local ctx = cases.context(p)
  local out = main.run(ctx)
  p:fact("outcome", out)
  if p.args.expect == "notSaved" then
    p:check("refused", out.ok == false)
    p:check("says to save first", #p.facts.shown == 1 and p.facts.shown[1].text == constants.MESSAGES.notSaved,
      p.facts.shown[1] and p.facts.shown[1].text)
  else
    -- past the guards the run reaches the dialog, which this context answers with a cancel
    p:check("reaches the dialog", p.facts.request ~= nil)
    p:check("a cancel changes nothing and says nothing", out.ok == false and #p.facts.shown == 0, out.text)
  end
end)
