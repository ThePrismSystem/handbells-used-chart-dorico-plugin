-- Which Dorico builds the plug-in runs on, and where it keeps its settings and temporary files.
local guards = require("hbuc.guards")
local constants = require("hbuc.constants")

return {
  any_dorico_6_is_supported = function(t)
    t:eq(guards.supported("6.2.30b6245"), true)
    t:eq(guards.supported("6.0.10"), true)
    t:eq(guards.supported("6.5.0b1"), true)
    t:eq(guards.supported("5.1.81"), false)
    t:eq(guards.supported("7.0.0"), false)
    t:eq(guards.supported("16.0.0"), false, "the major number, not its first digit")
    t:eq(guards.supported(nil), false)
    t:eq(constants.TESTED_DORICO, nil, "no list of tested builds any more")
  end,
  windows_folders = function(t)
    local f = guards.folders({ APPDATA = "C:\\Users\\u\\AppData\\Roaming", TEMP = "C:\\T\\" }, true)
    t:eq(f.data, "C:/Users/u/AppData/Roaming/Handbells Used Chart/")
    t:eq(f.temp, "C:/T/hbuc/")
  end,
  mac_folders = function(t)
    local f = guards.folders({ HOME = "/Users/u", TMPDIR = "/var/folders/x/T/" }, false)
    t:eq(f.data, "/Users/u/Library/Application Support/Handbells Used Chart/")
    t:eq(f.temp, "/var/folders/x/T/hbuc/")
    t:eq(guards.folders({ HOME = "/Users/u" }, false).temp, "/tmp/hbuc/")
  end,
  missing_folder_variables_raise = function(t)
    t:fails(function() guards.folders({ TEMP = "C:\\T" }, true) end)
    t:fails(function() guards.folders({}, false) end)
  end,
  any_temp_folder_for_a_last_message = function(t)
    t:eq(guards.anyTemp({ TEMP = "C:\\T" }, true), "C:/T/hbuc/")
    t:eq(guards.anyTemp({ TMP = "C:\\U\\" }, true), "C:/U/hbuc/")
    t:eq(guards.anyTemp({}, true), nil, "nowhere on Windows")
    t:eq(guards.anyTemp({ TMPDIR = "/var/T/" }, false), "/var/T/hbuc/")
    t:eq(guards.anyTemp({}, false), "/tmp/hbuc/")
  end,
}
