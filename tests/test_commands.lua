-- Dorico command strings, as proven by spike/11_chart_recipe.lua.
local commands = require("hbuc.commands")

return {
  layout_options_as_proven = function(t)
    t:eq(commands.layoutOptions(11, 0, { flowHeadingBehaviour = "kNoFlowHeadings" }),
      'Project.Layout.SetOptions?Dictionary=list: {string: "flowHeadingBehaviour"}\\, {string: "kNoFlowHeadings"}&OpenScoreID=11&LayoutIDArray=0')
    t:eq(commands.layoutOptions(13, 0, { ["staffLabelLayoutOptions.playersToShowPlayerName"] = "3,4" }),
      'Project.Layout.SetOptions?Dictionary=list: {string: "staffLabelLayoutOptions.playersToShowPlayerName"}\\, {string: "3\\,4"}&OpenScoreID=13&LayoutIDArray=0')
    t:eq(commands.layoutOptions(0, 2, { b = "y", a = "x" }),
      'Project.Layout.SetOptions?Dictionary=list: {string: "a"}\\, {string: "x"}\\, {string: "b"}\\, {string: "y"}&OpenScoreID=0&LayoutIDArray=2',
      "paths sorted")
  end,
  flow_notation_options = function(t)
    t:eq(commands.flowNotationOptions(15, 1, { ["barlineOptions.finalBarlineType"] = "kNone" }),
      'Project.Flow.SetNotationOptions?Dictionary=list: {string: "barlineOptions.finalBarlineType"}\\, {string: "kNone"}&OpenScoreID=15&FlowIDArray=1')
  end,
  backslash_escaped = function(t)
    t:eq(commands.layoutOptions(1, 0, { p = 'a\\b"c' }),
      'Project.Layout.SetOptions?Dictionary=list: {string: "p"}\\, {string: "a\\\\b\\"c"}&OpenScoreID=1&LayoutIDArray=0')
  end,
  option_values_refuse_ampersand_and_equals = function(t)
    t:fails(function() commands.layoutOptions(1, 0, { p = "a&b" }) end)
    t:fails(function() commands.layoutOptions(1, 0, { p = "a=b" }) end)
  end,
  build = function(t)
    t:eq(commands.build("Edit.SelectNone", {}), "Edit.SelectNone")
    t:eq(commands.build("File.Save", { { "Notify", "false" } }), "File.Save?Notify=false")
  end,
  select_command = function(t)
    t:eq(commands.select(1, 326, 36), "EventEdit.Select?FlowID=1&EventID=326&EventBlockID=36")
  end,
  renames_and_moves = function(t)
    t:eq(commands.renamePlayer(3, " "), "Project.Player.Rename?PlayerID=3&Name= &ShortName= ")
    t:eq(commands.renameFlow(1, "Handbells Used Chart"), "Project.Flow.Rename?FlowID=1&Name=Handbells Used Chart")
    t:eq(commands.moveFlowToStart(1), "Project.Flows.MoveToStart?FlowIDArray=1")
  end,
  set_mode_delete_layout_delete_flow = function(t)
    t:eq(commands.setMode("kSetupMode"), "Window.SwitchMode?WindowMode=kSetupMode")
    t:eq(commands.setMode("kWriteMode"), "Window.SwitchMode?WindowMode=kWriteMode")
    t:eq(commands.deleteLayout(7), "Project.Layouts.Delete?LayoutIDArray=7")
    t:eq(commands.deleteFlow(4), "Project.Flows.Delete?FlowIDArray=4")
    t:eq(commands.timeSignature("X"), "NoteInput.CreateTimeSignature?Definition=X")
  end,
  values_escape_ampersands_and_backslashes = function(t)
    -- proven in spike/30_param_escapes.lua: "P\&F" arrives as "P&F", "C\\D" as "C\D", and "=" needs nothing
    t:eq(commands.renameFlow(1, "P&F"), "Project.Flow.Rename?FlowID=1&Name=P\\&F")
    t:eq(commands.renamePlayer(1, "a=b"), "Project.Player.Rename?PlayerID=1&Name=a=b&ShortName=a=b")
    t:eq(commands.build("X", { { "K", "C\\D" } }), "X?K=C\\\\D")
    t:eq(commands.build("X", { { "K", "Ünïcødé" } }), "X?K=Ünïcødé")
  end,
  line_breaks_and_odd_keys_are_refused = function(t)
    t:fails(function() commands.build("X", { { "K", "line\nbreak" } }) end, "newline")
    t:fails(function() commands.build("X", { { "K&", "v" } }) end, "key with an ampersand")
    t:fails(function() commands.build("X", { { "K=", "v" } }) end, "key with an equals sign")
  end,
  player_name_only = function(t)
    -- Name alone: Dorico keeps the short name as it is
    t:eq(commands.renamePlayerName(4, "Handbells (P&F)"), "Project.Player.Rename?PlayerID=4&Name=Handbells (P\\&F)")
  end,
  missing_values_and_bad_ids_are_refused = function(t)
    t:fails(function() commands.build("X", { { "K", nil } }) end, "a missing value")
    t:fails(function() commands.select(1, nil, 36) end, "a missing event id")
    t:fails(function() commands.renamePlayer("3&x", "n") end, "an id that is not a number")
    t:fails(function() commands.deleteFlow(1.5) end, "a fractional id")
    t:fails(function() commands.layoutOptions(nil, 0, { a = "b" }) end, "a missing score id")
    t:eq(commands.deleteLayout("7"), "Project.Layouts.Delete?LayoutIDArray=7", "a digit string is an id")
  end,
}
