-- Which Dorico versions the plug-in runs on, and where it keeps its files.
local constants = require("hbuc.constants")

local guards = {}

-- versionString is app.versionString, such as "6.2.30b6245". Any Dorico 6 build is accepted, and issues on builds
-- not tested here are left for users to report; the run log records the exact build.
function guards.supported(versionString)
  return tostring(versionString or ""):match("^(%d+)%.") == constants.DORICO_MAJOR
end

local function folder(path)
  return (path:gsub("\\", "/"):gsub("/+$", "")) .. "/"
end

local function need(env, name)
  local v = env[name]
  if v == nil or v == "" then error(name .. " is not set, so the plug-in has nowhere to keep its files", 2) end
  return v
end

-- env: the environment variables (APPDATA and TEMP on Windows; HOME and TMPDIR on macOS). Forward slashes and a
-- trailing slash, so file names can be appended directly.
function guards.folders(env, isWindows)
  if isWindows then
    return {
      data = folder(need(env, "APPDATA")) .. "Handbells Used Chart/",
      temp = folder(need(env, "TEMP")) .. "hbuc/",
    }
  end
  local tmp = env.TMPDIR
  if tmp == nil or tmp == "" then tmp = "/tmp" end
  return {
    data = folder(need(env, "HOME")) .. "Library/Application Support/Handbells Used Chart/",
    temp = folder(tmp) .. "hbuc/",
  }
end

-- Somewhere to put the message of a run that could not start, from any temp variable set; nil when Windows has none.
function guards.anyTemp(env, isWindows)
  for _, name in ipairs({ "TEMP", "TMP", "TMPDIR" }) do
    if env[name] and env[name] ~= "" then return folder(env[name]) .. "hbuc/" end
  end
  if isWindows then return nil end
  return "/tmp/hbuc/"
end

return guards
