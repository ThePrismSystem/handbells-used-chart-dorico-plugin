-- JSON unit tests. Run under stock Lua (`lua52 spike/lib/test_json.lua`) or inside Dorico
-- (`python tools/dorico/run_lua.py spike/lib/test_json.lua`).
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./"
for name in pairs(package.loaded) do -- Dorico keeps one Lua state between runs: reload our modules
  if package.searchpath(name, here .. "?.lua") then package.loaded[name] = nil end
end
if not package.path:find(here .. "?.lua", 1, true) then package.path = here .. "?.lua;" .. package.path end
local json = require("json")

local failures = {}
local function eq(label, got, want)
  if got ~= want then
    failures[#failures + 1] = label .. ": got " .. tostring(got) .. ", want " .. tostring(want)
  end
end

local function run()
  eq("array", json.encode({ 1, 2, 3 }), "[1,2,3]")
  eq("object", json.encode({ a = "x" }), '{"a":"x"}')
  eq("escapes", json.encode('q"\n'), '"q\\"\\n"')
  eq("empty table", json.encode({}), "{}")
  eq("sorted keys", json.encode({ b = 1, a = 2 }), '{"a":2,"b":1}')
  eq("float", json.encode(1.5), "1.5")

  local d = json.decode('{"a":[1,true,null,"\\u00e9"]}')
  eq("decode number", d.a[1], 1)
  eq("decode true", d.a[2], true)
  eq("decode null", d.a[3], json.null)
  eq("decode unicode", d.a[4], "\195\169")

  local back = json.decode(json.encode({ runId = "r1", nested = { x = 1.5 } }))
  eq("round trip string", back.runId, "r1")
  eq("round trip nested", back.nested.x, 1.5)

  local ok = pcall(json.decode, "{bad")
  eq("malformed input errors", ok, false)
end

run()

if DoApp then
  local probe = require("probe")
  probe.run("test_json", function(p)
    p:check("all json assertions", #failures == 0, table.concat(failures, "; "))
  end)
else
  if #failures > 0 then
    for _, f in ipairs(failures) do print("FAIL " .. f) end
    os.exit(1)
  end
  print("json ok")
end
