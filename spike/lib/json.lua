-- The JSON module now lives in the plug-in package; the spike probes keep requiring it as "json".
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./"
return dofile(here .. "../../plugin/Handbells Used Chart/hbuc/json.lua")
