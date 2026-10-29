-- Asks for a MusicXML export when the score has noteheads Lua can't read (set in Dorico: docs/dorico-lua-guide.md,
-- section 2), and reads the files chosen. Dorico has no silent MusicXML export, and it is frozen while the plug-in
-- waits on its own windows, so the message offers to open Dorico's export dialog itself: the command waits until
-- that dialog closes, then the picker opens where the export went.
local commands = require("hbuc.commands")
local constants = require("hbuc.constants")
local musicxml = require("hbuc.musicxml")
local doc = require("hbuc.dorico.doc")
local files = require("hbuc.dorico.files")

local musicxmlstep = {}

local M, D = constants.MESSAGES, constants.DIALOG

local function folderOf(path)
  return tostring(path or ""):match("^(.*[/\\])") or ""
end

local function nameOf(path)
  return tostring(path):match("([^/\\]+)$") or tostring(path)
end

local function newest(list)
  local best
  for _, e in ipairs(list or {}) do
    if not best or (e.modified or 0) > (best.modified or 0) then best = e end
  end
  return best
end

local function message(ctx, chartExists)
  local buttons = { { id = "export", label = D.exportMusicXML }, { id = "choose", label = D.chooseFile } }
  if chartExists then buttons[#buttons + 1] = { id = "remove", label = D.removeChart } end
  buttons[#buttons + 1] = { id = "cancel", label = D.cancel }
  return ctx.choose({ title = D.resultsTitle, text = M.musicxmlNeeded, buttons = buttons, cancel = "cancel" })
end

-- Where the picker starts after Dorico's export: the folder of what it just wrote, with every file of it picked,
-- largest (a full score) first. Each flow has its own full-score file, and the pairing ignores the parts'. Nil when
-- the export wrote nothing that can be seen.
local function afterExport(ctx, projectDir)
  local before = files.exports(projectDir)
  local was = newest(before)
  doc.command(ctx.app, ctx.log, commands.build("File.Export", { { "FilterID", "MusicXMLExportFilter" } }))
  local after = files.exports(projectDir)
  -- Without lfs, or for a folder it can't list, nothing can be seen either way: go on to the picker.
  if not before or not after then return { folder = projectDir } end
  local fresh = {}
  for _, e in ipairs(after) do
    if not was or (e.modified or 0) > (was.modified or 0) then fresh[#fresh + 1] = e end
  end
  local latest = newest(fresh)
  if not latest then return nil end
  local folder, here = folderOf(latest.path), {}
  for _, e in ipairs(fresh) do
    if folderOf(e.path) == folder then here[#here + 1] = e end
  end
  table.sort(here, function(a, b) return (a.size or 0) > (b.size or 0) end)
  local names = {}
  for i, e in ipairs(here) do names[i] = nameOf(e.path) end
  return { folder = folder, files = names }
end

-- A message or picker that couldn't be shown: the run says so rather than ending as if cancelled.
local function failed()
  return { status = "error", text = D.dialogFailed }
end

-- The parsed files, or "back" (to the message), or an error outcome. shown: the paths as the picker showed them,
-- for messages.
local function readChosen(ctx, paths, shown, projectPath, exported)
  local parsed = {}
  for i, path in ipairs(paths) do
    local name = nameOf(shown[i] or path)
    local text = files.read(path)
    if not text then return { status = "error", text = string.format(M.musicxmlCannotOpen, name) } end
    local result, why = musicxml.parse(text)
    if why == "compressed" or path:lower():match("%.mxl$") then
      ctx.show("warning", M.musicxmlCompressed)
      return "back"
    end
    if not result then return { status = "error", text = string.format(M.musicxmlUnreadable, name) } end
    parsed[#parsed + 1] = result
  end
  -- An export made before noteheads were changed still matches the notes, so a chosen file older than the last
  -- save is questioned. The one just exported never is.
  local saved = not exported and files.modified(projectPath)
  if saved then
    for _, path in ipairs(paths) do
      local made = files.modified(path)
      if made and made < saved then
        local go = ctx.choose({ title = D.resultsTitle, text = M.musicxmlOlder,
          buttons = { { id = "use", label = D.useAnyway }, { id = "back", label = D.back } }, cancel = "back" })
        if not go then return failed() end
        if go ~= "use" then return "back" end
        break
      end
    end
  end
  return { status = "files", files = parsed }
end

-- args: {chartExists, projectPath}. Returns {status = "files", files = {parsed...}}, {status = "cancel"},
-- {status = "remove"} or {status = "error", text}.
function musicxmlstep.run(ctx, args)
  local projectDir = folderOf(args.projectPath)
  while true do
    local answer = message(ctx, args.chartExists)
    if not answer then return failed() end
    if answer == "remove" then return { status = "remove" } end
    if answer ~= "export" and answer ~= "choose" then return { status = "cancel" } end
    local start
    if answer == "export" then
      start = afterExport(ctx, projectDir)
    else
      local latest = newest(files.exports(projectDir))
      start = { folder = latest and folderOf(latest.path) or projectDir }
    end
    if start then
      local paths, shown = ctx.pick({ title = D.pickTitle, folder = start.folder, files = start.files,
        filter = { name = D.pickFilter, extensions = { "musicxml", "xml" } } })
      if not paths then return failed() end
      if #paths == 0 then return { status = "cancel" } end
      local outcome = readChosen(ctx, paths, shown or {}, args.projectPath, answer == "export")
      if outcome ~= "back" then return outcome end
    end
  end
end

return musicxmlstep
