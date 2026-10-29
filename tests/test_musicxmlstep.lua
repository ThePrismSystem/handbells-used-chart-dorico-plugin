-- The MusicXML step, with Dorico, the files and the dialog scripts stubbed: what the director is asked, in what order,
-- and what the run gets back.
local constants = require("hbuc.constants")

local SCORE = '<score-partwise><part-list><score-part id="P1"><part-name>A</part-name></score-part></part-list>'
  .. '<part id="P1"><measure><note><pitch><step>C</step><octave>4</octave></pitch><duration>1</duration></note>'
  .. "</measure></part></score-partwise>"

-- o: {answers = {...} (the message's answers, in order; none left is a window that failed), picks = {{paths...,
-- shown = {...}} or false for a picker that failed}, texts = {[path] = text}, exports = {before, after} (listings, nil
-- for no lfs), modified = {[path] = time}}.
-- Returns the outcome and what was asked: choices, picks, commands, shown.
local function step(o)
  local asked = { choices = {}, picks = {}, commands = {}, shown = {} }
  local listings = o.exports or {}
  local listed = 0
  local saved = {}
  for _, name in ipairs({ "hbuc.dorico.files", "hbuc.dorico.doc", "hbuc.dorico.musicxmlstep" }) do
    saved[name] = package.loaded[name]
  end
  package.loaded["hbuc.dorico.files"] = {
    read = function(path) return (o.texts or {})[path] end,
    modified = function(path) return (o.modified or {})[path] end,
    exports = function()
      listed = listed + 1
      if o.exports == nil then return nil end
      return listings[math.min(listed, #listings)]
    end,
  }
  package.loaded["hbuc.dorico.doc"] = { command = function(_, _, text) asked.commands[#asked.commands + 1] = text end }
  package.loaded["hbuc.dorico.musicxmlstep"] = nil
  local answers, picks = o.answers or {}, o.picks or {}
  local ctx = {
    app = {}, log = { line = function() end },
    choose = function(choice)
      asked.choices[#asked.choices + 1] = choice
      return answers[#asked.choices]
    end,
    pick = function(pick)
      asked.picks[#asked.picks + 1] = pick
      local paths = picks[#asked.picks]
      if paths == false then return nil end
      return paths or {}, paths and paths.shown
    end,
    show = function(kind, text) asked.shown[#asked.shown + 1] = { kind = kind, text = text } end,
  }
  local ok, out = pcall(function()
    return require("hbuc.dorico.musicxmlstep").run(ctx, { chartExists = o.chartExists, projectPath = "C:/p/Bells.dorico" })
  end)
  for name, m in pairs(saved) do package.loaded[name] = m end
  if not ok then error(out, 0) end
  return out, asked
end

local function ids(choice)
  local out = {}
  for _, b in ipairs(choice.buttons) do out[#out + 1] = b.id end
  return table.concat(out, ",")
end

local OLD = { path = "C:/p/Flows from Bells/Bells - Full score - 01 Bells.musicxml", modified = 100, size = 900 }
local FULL = { path = "C:/p/Flows from Bells/Bells - Full score - 01 Bells.musicxml", modified = 200, size = 900 }
local PART = { path = "C:/p/Flows from Bells/Bells - Handbells - 01 Bells.musicxml", modified = 200, size = 300 }
local OLD_ELSEWHERE = { path = "C:/p/Flows from Old/Old - Full score - 01 Old.musicxml", modified = 50, size = 5000 }

return {
  cancel_ends_the_step = function(t)
    local out, asked = step({ answers = { "cancel" } })
    t:eq(out.status, "cancel")
    t:eq(#asked.picks, 0)
    t:eq(asked.choices[1].text, constants.MESSAGES.musicxmlNeeded)
    t:eq(asked.choices[1].cancel, "cancel")
  end,
  a_window_that_fails_says_so = function(t)
    local function failed(o, what)
      local out = step(o)
      t:eq(out.status, "error", what)
      t:eq(out.text, constants.DIALOG.dialogFailed, what)
    end
    failed({ answers = {} }, "the message")
    failed({ answers = { "choose" }, exports = { {} }, picks = { false } }, "the picker")
    failed({ answers = { "choose" }, exports = { { OLD } }, picks = { { OLD.path } }, texts = { [OLD.path] = SCORE },
      modified = { [OLD.path] = 100, ["C:/p/Bells.dorico"] = 150 } }, "the question about an older file")
  end,
  messages_name_a_file_as_the_picker_showed_it = function(t)
    -- on Windows the path Lua opens is in the code page, and the one the picker showed is in UTF-8
    local out = step({ answers = { "choose" }, exports = { {} },
      picks = { { "C:/p/No\235l.musicxml", shown = { "C:/p/No\195\171l.musicxml" } } } })
    t:eq(out.text, string.format(constants.MESSAGES.musicxmlCannotOpen, "No\195\171l.musicxml"))
  end,
  remove_is_offered_only_with_a_chart = function(t)
    local _, asked = step({ answers = { "cancel" } })
    t:eq(ids(asked.choices[1]), "export,choose,cancel")
    local out, withChart = step({ answers = { "remove" }, chartExists = true })
    t:eq(ids(withChart.choices[1]), "export,choose,remove,cancel")
    t:eq(withChart.choices[1].buttons[3].label, constants.DIALOG.removeChart)
    t:eq(out.status, "remove")
  end,
  export_runs_the_command_then_picks_the_full_score = function(t)
    local out, asked = step({ answers = { "export" }, exports = { { OLD_ELSEWHERE }, { OLD_ELSEWHERE, FULL, PART } },
      picks = { { FULL.path } }, texts = { [FULL.path] = SCORE } })
    t:eq(asked.commands[1], "File.Export?FilterID=MusicXMLExportFilter")
    t:eq(asked.picks[1].folder, "C:/p/Flows from Bells/")
    -- every file the export just wrote (not an older, larger one elsewhere), full score first: each flow has its
    -- own, and a part's file pairs only for the players it holds
    t:eq(table.concat(asked.picks[1].files, "|"),
      "Bells - Full score - 01 Bells.musicxml|Bells - Handbells - 01 Bells.musicxml")
    t:eq(out.status, "files")
    t:eq(#out.files, 1)
    t:eq(out.files[1].parts[1].name, "A")
  end,
  a_cancelled_export_goes_back_to_the_message = function(t)
    local out, asked = step({ answers = { "export", "cancel" }, exports = { { OLD }, { OLD } } })
    -- cancelled, or written somewhere else: either way there is nothing new to preselect
    t:eq(asked.shown[1].text, constants.MESSAGES.musicxmlNotFound)
    t:eq(#asked.choices, 2, "asked again")
    t:eq(#asked.picks, 0)
    t:eq(out.status, "cancel")
  end,
  without_lfs_an_export_goes_straight_to_the_picker = function(t)
    local out, asked = step({ answers = { "export" }, picks = { {} } })
    t:eq(#asked.picks, 1)
    t:eq(asked.picks[1].folder, "C:/p/")
    t:eq(asked.picks[1].files, nil)
    t:eq(out.status, "cancel", "a cancelled picker ends the step")
  end,
  choose_starts_in_the_newest_export = function(t)
    local _, asked = step({ answers = { "choose" }, exports = { { OLD, PART } } })
    t:eq(asked.picks[1].folder, "C:/p/Flows from Bells/")
    t:eq(asked.picks[1].files, nil, "nothing preselected")
    t:eq(asked.picks[1].filter.extensions[1], "musicxml")
    local _, none = step({ answers = { "choose" }, exports = { {} } })
    t:eq(none.picks[1].folder, "C:/p/", "the project's folder when there is no export")
  end,
  a_compressed_file_warns_and_goes_back = function(t)
    local out, asked = step({ answers = { "choose", "cancel" }, exports = { {} }, picks = { { "C:/p/x.mxl" } },
      texts = { ["C:/p/x.mxl"] = "PK\3\4zip" } })
    t:eq(asked.shown[1].text, constants.MESSAGES.musicxmlCompressed)
    t:eq(#asked.choices, 2, "back to the message")
    t:eq(out.status, "cancel")
  end,
  an_unreadable_file_is_an_error = function(t)
    local out = step({ answers = { "choose" }, exports = { {} }, picks = { { "C:/p/notes.xml" } },
      texts = { ["C:/p/notes.xml"] = "<html/>" } })
    t:eq(out.status, "error")
    t:eq(out.text, string.format(constants.MESSAGES.musicxmlUnreadable, "notes.xml"))
  end,
  a_file_that_cannot_be_opened_says_so = function(t)
    local out = step({ answers = { "choose" }, exports = { {} }, picks = { { "C:/p/\227\131\153\227\131\171.musicxml" } } })
    t:eq(out.status, "error")
    t:eq(out.text, string.format(constants.MESSAGES.musicxmlCannotOpen, "\227\131\153\227\131\171.musicxml"))
  end,
  an_older_chosen_file_asks_first = function(t)
    local o = { answers = { "choose", "back", "cancel" }, exports = { { OLD } }, picks = { { OLD.path } },
      texts = { [OLD.path] = SCORE }, modified = { [OLD.path] = 100, ["C:/p/Bells.dorico"] = 150 } }
    local out, asked = step(o)
    t:eq(asked.choices[2].text, constants.MESSAGES.musicxmlOlder)
    t:eq(ids(asked.choices[2]), "use,back")
    t:eq(#asked.choices, 3, "back to the message")
    t:eq(out.status, "cancel")
    o.answers = { "choose", "use" }
    t:eq(step(o).status, "files", "or on with it")
  end,
  an_older_file_picked_after_an_export_still_asks = function(t)
    -- what the export just wrote is newer than the last save, but the picker can be pointed at anything
    local out, asked = step({ answers = { "export" }, exports = { {}, { FULL } }, picks = { { FULL.path } },
      texts = { [FULL.path] = SCORE }, modified = { [FULL.path] = 200, ["C:/p/Bells.dorico"] = 150 } })
    t:eq(#asked.choices, 1, "the new export isn't questioned")
    t:eq(out.status, "files")
    out, asked = step({ answers = { "export", "use" }, exports = { {}, { FULL } }, picks = { { OLD_ELSEWHERE.path } },
      texts = { [OLD_ELSEWHERE.path] = SCORE }, modified = { [OLD_ELSEWHERE.path] = 50, ["C:/p/Bells.dorico"] = 150 } })
    t:eq(asked.choices[2].text, constants.MESSAGES.musicxmlOlder)
    t:eq(out.status, "files")
  end,
  a_file_with_no_music_is_skipped = function(t)
    -- Dorico writes an empty <score-partwise/> for a flow made in the same run, and the picker preselects it too
    local empty = "<score-partwise/>"
    local out = step({ answers = { "choose" }, exports = { {} }, picks = { { "C:/p/a.musicxml", "C:/p/b.musicxml" } },
      texts = { ["C:/p/a.musicxml"] = empty, ["C:/p/b.musicxml"] = SCORE } })
    t:eq(out.status, "files")
    t:eq(#out.files, 1)
    out = step({ answers = { "choose" }, exports = { {} }, picks = { { "C:/p/a.musicxml" } },
      texts = { ["C:/p/a.musicxml"] = empty } })
    t:eq(out.status, "error", "but there has to be music in one")
    t:eq(out.text, string.format(constants.MESSAGES.musicxmlUnreadable, "a.musicxml"))
  end,
}
