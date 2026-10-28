-- Dorico runs Lua 5.2 with its compatibility functions turned on (the plug-in calls unpack).
std = "lua52c"
-- Line length isn't checked, since rewrapping the long lines would only add churn.
max_line_length = false

-- Dorico's object model. Layer 1 (hbuc/*.lua) gets none of it, which tests/test_layer1_is_pure.lua also checks.
local dorico = { "DoApp", "DoCore" }
files["plugin/Handbells Used Chart/hbuc/dorico/**/*.lua"] = { read_globals = dorico }
files["spike/**/*.lua"] = { read_globals = dorico }
files["tests/dorico/**/*.lua"] = { read_globals = dorico }
files["fixtures/**/*.lua"] = { read_globals = dorico }
-- These tests stand in for Dorico's globals and the runner's.
files["spike/lib/test_events.lua"] = { globals = { "DoCore", "HBUC_RUN" } }
files["tests/test_readscore.lua"] = { globals = { "DoCore" } }
