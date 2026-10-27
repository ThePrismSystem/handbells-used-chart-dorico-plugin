-- The event parser now lives in the plug-in package (hbuc/eventtext.lua, which reads exact fractions and double
-- sharps); the spike probes keep requiring it as "events".
local here = debug.getinfo(1, "S").source:match("^@(.*[/\\])") or "./"
return dofile(here .. "../../plugin/Handbells Used Chart/hbuc/eventtext.lua")
