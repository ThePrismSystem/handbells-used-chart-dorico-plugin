-- For tests/dialog/test_windows_dialog.py, with stock Lua: writes a dialog request like the plug-in's, or reads a
-- response back the way the plug-in does.
--   lua52 make_request.lua request <fixture|single|many|cased> <request.json> [settings json] [run id, default t1]
--   lua52 make_request.lua parse <request.json> <response.json>     prints request.parse's result as JSON
local here = (arg[0]:match("^(.*[/\\])") or "./")
package.path = here .. "../../plugin/Handbells Used Chart/?.lua;" .. package.path
local json = require("hbuc.json")
local options = require("hbuc.options")
local request = require("hbuc.request")

local function read(path)
  local f = assert(io.open(path, "rb"))
  local s = f:read("*a")
  f:close()
  return s
end

local function rec(head, colour, instrument)
  return { pitch = 72, diatonic = 35, head = head, colour = colour or "", instrument = instrument }
end

if arg[1] == "request" then
  local players, records
  if arg[2] == "single" then
    players = { "Handbells" }
    records = { rec("noteheadset.default", "", "Handbells") }
  elseif arg[2] == "cased" then
    players = { "Handbells", "HANDBELLS" }
    records = { rec("noteheadset.default", "", "Handbells"), rec("noteheadset.default", "", "HANDBELLS") }
  elseif arg[2] == "many" then
    players, records = {}, {}
    for i = 1, 25 do
      players[i] = "Player " .. i
      records[i] = rec("noteheadset.default", "", players[i])
    end
  else
    players = { "Handbells (A)", "Handbells (B)", "Organ" }
    records = {
      rec("noteheadset.default", "", "Handbells (A)"),
      rec("noteheadset.diamondNoteheads", "#c80000", "Handbells (A)"),
      rec("noteheadset.diamondNoteheads", "#c80000", "Handbells (A)"),
      rec("noteheadset.Xnoteheads", "", "Handbells (A)"),
      rec("noteheadset.rectangular", "#008000", "Handbells (B)"),
      rec("noteheadset.triangleDownNoteheads", "#e628fa", "Handbells (B)"),
      rec("noteheadset.triangleUpNoteheads", "", "Handbells (B)"),
      rec("noteheadset.default", "", "Organ"),
    }
  end
  local req = request.build({ players = players, records = records, settings = options.decodeSettings(arg[4] or ""),
    chartExists = false, runId = arg[5] or "t1" })
  local f = assert(io.open(arg[3], "wb"))
  f:write(json.encode(req))
  f:close()
elseif arg[1] == "parse" then
  local req = json.decode(read(arg[2]))
  local ok, raw = pcall(json.decode, read(arg[3]))
  io.write(json.encode(request.parse(ok and raw or nil, req) or { parsed = false }))
end
