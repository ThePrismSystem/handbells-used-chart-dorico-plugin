-- Start a Windows Forms dialog from Dorico's Lua and pass JSON both ways.
-- args.autoClose (default true): the dialog presses OK itself after a second.
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])")
local mine = here .. "?.lua;" .. here .. "lib/?.lua;" .. here .. "../spike/lib/?.lua"
for name in pairs(package.loaded) do -- Dorico keeps one Lua state between runs: reload our modules
  if package.searchpath(name, mine) then package.loaded[name] = nil end
end
if not package.path:find(mine, 1, true) then package.path = mine .. ";" .. package.path end
local probe = require("probe")
local json = require("json")

local function win(path) return (path:gsub("/", "\\")) end

probe.run("09_dialog", function(p)
  local app = DoApp.DoApp()
  local dir = os.getenv("TEMP") .. "\\hbuc-run\\"
  local reqPath, respPath = dir .. "dialog-request.json", dir .. "dialog-response.json"
  os.remove(respPath)
  local players = {}
  for i, pl in ipairs(app.currentScore.players) do players[i] = tostring(pl) end
  local f = assert(io.open(reqPath, "wb"))
  f:write(json.encode({ players = players, noteheads = { "noteheadset.default", "noteheadset.diamondNoteheads" } }))
  f:close()

  local script = win(here .. "dialog_probe.ps1")
  local auto = p.args.autoClose == nil or p.args.autoClose == true
  local cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' .. script .. '" -Request "'
    .. reqPath .. '" -Response "' .. respPath .. '"' .. (auto and " -AutoClose" or "")
  p:fact("command", cmd)
  local t0 = os.time()
  local a, b, c = os.execute(cmd)
  p:fact("elapsedSeconds", os.time() - t0)
  p:fact("osExecute", tostring(a) .. " " .. tostring(b) .. " " .. tostring(c))

  local rf = io.open(respPath, "rb")
  p:check("dialog wrote a response", rf ~= nil)
  if not rf then return end
  local resp = json.decode(rf:read("*a"))
  rf:close()
  p:fact("response", resp)
  p:check("not cancelled", resp.cancelled == false, tostring(resp.cancelled))
  p:check("notehead is one we offered", resp.notehead == "noteheadset.default" or resp.notehead == "noteheadset.diamondNoteheads", resp.notehead)
end)
