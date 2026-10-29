-- Reading and writing the plug-in's own files. lfs ships with Dorico on Windows (docs/dorico-lua-guide.md,
-- section 1); a Mac without it makes folders with mkdir and goes without modification times.
local shell = require("hbuc.shell")

local files = {}

local function lfsOrNil()
  local found, lfs = pcall(require, "lfs")
  if found then return lfs end
  return nil
end

function files.read(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local text = f:read("*a")
  f:close()
  return text
end

function files.write(path, text)
  local f, err = io.open(path, "wb")
  if not f then error("cannot write " .. path .. ": " .. tostring(err)) end
  f:write(text)
  f:close()
end

-- A missing file is no error: callers remove what may or may not be there.
function files.remove(path)
  os.remove(path)
end

-- Makes every missing folder along path (forward slashes, as guards.folders gives them).
function files.ensureDir(path)
  local lfs = lfsOrNil()
  if not lfs then
    if not os.execute("/bin/mkdir -p " .. shell.quoteSh(path)) then error("cannot make folder " .. path) end
    return
  end
  local sofar = ""
  for part in path:gmatch("[^/]+") do
    sofar = (sofar == "" and not path:match("^/")) and part or (sofar .. "/" .. part)
    if not sofar:match("^%a:$") and lfs.attributes(sofar, "mode") == nil then
      local ok, err = lfs.mkdir(sofar)
      if not ok and lfs.attributes(sofar, "mode") == nil then error("cannot make folder " .. sofar .. ": " .. tostring(err)) end
    end
  end
end

-- nil without lfs: main then cannot tell a save that did nothing, and goes on.
function files.modified(path)
  local lfs = lfsOrNil()
  if not lfs then return nil end
  return lfs.attributes(path, "modification")
end

return files
