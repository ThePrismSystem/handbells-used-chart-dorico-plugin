-- files.exports, with LuaFileSystem stubbed: the MusicXML files in a folder's "Flows from …" subfolders, where
-- Dorico's export puts them by default.

-- tree: {[folder path] = {[name] = {mode = "directory"} or {mode = "file", modification, size}}}
local function exportsIn(tree, folder)
  local function entry(path)
    local dir, name = path:match("^(.*/)([^/]+)/?$")
    return dir and tree[dir] and tree[dir][name]
  end
  local fake = {
    dir = function(path)
      if not tree[path] then error("cannot open " .. path) end
      local names = {}
      for name in pairs(tree[path]) do names[#names + 1] = name end
      table.sort(names)
      local i = 0
      return function()
        i = i + 1
        return names[i]
      end
    end,
    attributes = function(path, field)
      local e = entry(path)
      if not e then return nil end
      if field then return e[field] end
      return e
    end,
  }
  local saved = package.loaded.lfs
  package.loaded.lfs = fake
  package.loaded["hbuc.dorico.files"] = nil
  local ok, out = pcall(function() return require("hbuc.dorico.files").exports(folder) end)
  package.loaded.lfs = saved
  package.loaded["hbuc.dorico.files"] = nil
  if not ok then error(out, 0) end
  return out
end

local TREE = {
  ["C:/p/"] = {
    ["Bells.dorico"] = { mode = "file", modification = 1, size = 10 },
    ["Flows from Bells"] = { mode = "directory" },
    ["Old exports"] = { mode = "directory" },
  },
  ["C:/p/Flows from Bells/"] = {
    ["Bells - Full score - 01 Bells.musicxml"] = { mode = "file", modification = 5, size = 900 },
    ["Bells - Handbells - 01 Bells.MXL"] = { mode = "file", modification = 6, size = 100 },
    ["notes.txt"] = { mode = "file", modification = 7, size = 1 },
  },
  ["C:/p/Old exports/"] = {
    ["old.musicxml"] = { mode = "file", modification = 2, size = 50 },
  },
}

return {
  exports_lists_flows_from_folders_only = function(t)
    local list = exportsIn(TREE, "C:/p/")
    t:eq(#list, 2, "the two MusicXML files, compressed or not, and not the other folder's")
    table.sort(list, function(a, b) return a.path < b.path end)
    t:eq(list[1].path, "C:/p/Flows from Bells/Bells - Full score - 01 Bells.musicxml")
    t:eq(list[1].modified, 5)
    t:eq(list[1].size, 900)
    t:eq(list[2].path, "C:/p/Flows from Bells/Bells - Handbells - 01 Bells.MXL")
  end,
  a_folder_that_cannot_be_listed_is_nil = function(t)
    t:eq(exportsIn(TREE, "C:/missing/"), nil)
    t:eq(exportsIn(TREE, ""), nil)
  end,
}
