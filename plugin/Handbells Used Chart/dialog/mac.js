// Handbells Used Chart: the settings dialog, the results window, and the questions asked before the dialog on a Mac,
// in JavaScript for Automation with the AppKit bridge. Nothing to install or compile, so it runs the same on Apple
// silicon and Intel Macs.
// Started by the plug-in (hbuc/dorico/dialog.lua) with os.execute; Dorico waits until it closes.
//
//   osascript -l JavaScript mac.js <request.json> <response.json>   the settings dialog
//   osascript -l JavaScript mac.js --message <message.json>        the results window: {"title", "kind", "text"}
//   osascript -l JavaScript mac.js --choice <choice.json> <response.json>   a message with buttons: {"choice": id}
//
// The request is what hbuc/request.lua builds, and the response has dialog/windows.ps1's shape (see its header),
// written as UTF-8. An answer is always written: if the dialog cannot be shown, a cancel carrying the error.
//
// The parts above run() touch no AppKit, so tests/dialog/test_mac_script.py runs them under Node. AppKit constants
// are written as numbers, since the bridge may not know newer names; each is named where it is used.

// ------------------------------------------------------------------------------------------------ the request

// Lua writes an empty list as {}, and a one-item list may come as a bare value.
function toList(value) {
  if (value === undefined || value === null) return [];
  if (Array.isArray(value)) return value;
  if (typeof value === "object" && Object.keys(value).length === 0) return [];
  return [value];
}

function field(object, name) {
  if (object === undefined || object === null || typeof object !== "object") return undefined;
  return Object.prototype.hasOwnProperty.call(object, name) ? object[name] : undefined;
}

function text(value) {
  return value === undefined || value === null ? "" : String(value);
}

// The request with every list a list and every name a string.
function requestModel(req) {
  const noteheads = toList(field(req, "noteheads"));
  const runId = field(req, "runId");
  return {
    title: text(field(req, "title")),
    version: text(field(req, "version")),
    runId: runId === undefined ? null : runId,
    labels: field(req, "labels") || {},
    instruments: toList(field(req, "instruments")).map(text),
    selected: toList(field(req, "selected")).map(text),
    atPitch: toList(field(req, "atPitch")).map(text),
    headIds: noteheads.map(function (h) { return text(field(h, "id")); }),
    headNames: noteheads.map(function (h) { return text(field(h, "name")); }),
    shapes: toList(field(req, "shapes")).map(text),
    modes: toList(field(req, "modes")).map(text),
    mode: text(field(req, "mode")),
    newPage: field(req, "newPage") !== false,
    kinds: toList(field(req, "kinds")),
    colours: field(req, "colours") || {},
  };
}

// Handbells are always black, so only the other kinds have a colour field.
function hasColour(kind) {
  const label = field(kind, "colourLabel");
  return label !== undefined && label !== null;
}

// The choices the dialog opens with: one entry per instrument, and one per kind.
function initialPicks(model) {
  return {
    ticked: model.instruments.map(function (name) { return model.selected.indexOf(name) >= 0; }),
    atPitch: model.instruments.map(function (name) { return model.atPitch.indexOf(name) >= 0; }),
    mode: model.modes.indexOf(model.mode) >= 0 ? model.mode : (model.modes[0] || ""),
    newPage: model.newPage,
    heads: model.kinds.map(function (k) { return Math.max(0, model.headIds.indexOf(text(field(k, "head")))); }),
    shapes: model.kinds.map(function (k) {
      const shape = text(field(k, "shape"));
      return model.shapes.indexOf(shape) >= 0 ? shape : (model.shapes[0] || "");
    }),
    colours: model.kinds.map(function (k) { return text(field(k, "colour")); }),
    remove: false,
  };
}

// The answer for OK: picks.heads holds notehead indexes; everything else holds what the controls show.
function settingsResponse(model, picks) {
  const heads = {};
  const shapes = {};
  const colours = {};
  model.kinds.forEach(function (k, i) {
    const kind = text(field(k, "kind"));
    heads[kind] = model.headIds[picks.heads[i]];
    shapes[kind] = picks.shapes[i];
    if (hasColour(k)) colours[kind] = picks.colours[i];
  });
  return {
    version: model.version,
    runId: model.runId,
    cancelled: false,
    instruments: model.instruments.filter(function (_, i) { return picks.ticked[i]; }),
    atPitch: model.instruments.filter(function (_, i) { return picks.atPitch[i]; }),
    mode: picks.mode,
    newPage: picks.newPage !== false,
    heads: heads,
    shapes: shapes,
    colours: colours,
    remove: Boolean(picks.remove),
  };
}

function cancelResponse(model, error) {
  const response = { version: model.version, runId: model.runId, cancelled: true };
  if (error !== undefined) response.error = String(error);
  return response;
}

// A choice alert's answer: NSAlertFirstButtonReturn (1000) is the first button, and so on. Anything else is the
// cancel button, as closing the Windows window is.
function choiceResponse(choice, code) {
  const button = toList(field(choice, "buttons"))[code - 1000];
  return { choice: button ? text(field(button, "id")) : text(field(choice, "cancel")) };
}

// Picking a notehead puts the colour most of its notes carry into that instrument's colour field.
function colourFor(model, headIndex) {
  return text(field(model.colours, model.headIds[headIndex]));
}

// Charting one instrument apart is the same as charting it combined.
function chartsEnabled(ticked) {
  return ticked.filter(Boolean).length > 1;
}

// The settings window's width: the usual one, or wider when the "Written as" pop-up needs more for its longest
// choice. writtenWidth is that pop-up's fitted width (AppKit measures it). A row puts the pop-up WRITTEN_X in and
// leaves 20 after it, and the list's border and scroller take 20 more.
function settingsWidth(writtenWidth) {
  return Math.max(WIDTH, 2 * MARGIN + WRITTEN_X + 20 + 20 + Math.ceil(writtenWidth));
}

// ------------------------------------------------------------------------------------------------ AppKit

const UTF8 = 4; // NSUTF8StringEncoding
const WIDTH = 660;
const MARGIN = 20;
const ROW = 28; // an instrument row
const WRITTEN_X = 290; // where a row's "Written as" pop-up starts

function readText(path) {
  const value = $.NSString.stringWithContentsOfFileEncodingError(path, UTF8, null);
  if (value.isNil()) throw new Error("cannot read " + path);
  return ObjC.unwrap(value);
}

function writeText(path, value) {
  if (!$(value).writeToFileAtomicallyEncodingError(path, true, UTF8, null)) throw new Error("cannot write " + path);
}

function rect(x, y, w, h) {
  return $.NSMakeRect(x, y, w, h);
}

// Dorico is in front, and this script is another process: come forward and take the keyboard.
function activate(app) {
  app.activateIgnoringOtherApps(true);
  if (app.respondsToSelector("activate")) app.activate; // macOS 14 and later
}

function addLabel(view, value, x, y, w, style) {
  const label = $.NSTextField.labelWithString(text(value));
  label.setFrame(rect(x, y, w, 18));
  label.setLineBreakMode(4); // NSLineBreakByTruncatingTail
  if (style === "bold") label.setFont($.NSFont.boldSystemFontOfSize($.NSFont.systemFontSize));
  if (style === "grey") label.setTextColor($.NSColor.secondaryLabelColor);
  view.addSubview(label);
  return label;
}

// A pop-up's width when it fits its longest title.
function fittedWidth(titles) {
  const popup = $.NSPopUpButton.alloc.initWithFramePullsDown(rect(0, 0, 100, 26), false);
  titles.forEach(function (title) { popup.addItemWithTitle(text(title)); });
  popup.sizeToFit;
  return popup.frame.size.width;
}

// Items go in one by one: the pop-up's own addItemWithTitle drops a second item with the same title. Items made
// that way have no action, which automatic enabling would grey out.
function addPopup(view, titles, x, y, w, target, action, tag) {
  const popup = $.NSPopUpButton.alloc.initWithFramePullsDown(rect(x, y, w, 26), false);
  popup.setAutoenablesItems(false);
  titles.forEach(function (title) {
    const item = $.NSMenuItem.alloc.init;
    item.setTitle(text(title));
    popup.menu.addItem(item);
  });
  if (titles.length > 0) popup.selectItemAtIndex(0);
  if (action) {
    popup.setTarget(target);
    popup.setAction(action);
  }
  popup.setTag(tag || 0);
  view.addSubview(popup);
  return popup;
}

function addCheckbox(view, title, x, y, w, target, action) {
  const box = $.NSButton.alloc.initWithFrame(rect(x, y, w, 18));
  box.setButtonType(3); // NSButtonTypeSwitch
  box.setTitle(text(title));
  if (action) {
    box.setTarget(target);
    box.setAction(action);
  }
  view.addSubview(box);
  return box;
}

function addButton(view, title, x, y, w, target, action, key) {
  const button = $.NSButton.alloc.initWithFrame(rect(x, y, w, 32));
  button.setBezelStyle(1); // NSBezelStyleRounded (Push)
  button.setTitle(text(title));
  button.setTarget(target);
  button.setAction(action);
  button.setKeyEquivalent(key);
  view.addSubview(button);
  return button;
}

// Views whose y runs down the page, like the Windows layout; and the target the controls' actions call.
function registerClasses(handlers) {
  ObjC.registerSubclass({
    name: "HbucFlippedView",
    superclass: "NSView",
    methods: { isFlipped: { types: ["bool", []], implementation: function () { return true; } } },
  });
  ObjC.registerSubclass({
    name: "HbucTarget",
    superclass: "NSObject",
    methods: {
      "ok:": { types: ["void", ["id"]], implementation: function (sender) { handlers.ok(sender); } },
      "cancel:": { types: ["void", ["id"]], implementation: function (sender) { handlers.cancel(sender); } },
      "ticked:": { types: ["void", ["id"]], implementation: function (sender) { handlers.ticked(sender); } },
      "headPicked:": { types: ["void", ["id"]], implementation: function (sender) { handlers.headPicked(sender); } },
    },
  });
}

function showSettings(app, model) {
  const labels = model.labels;
  const picks = initialPicks(model);
  const ui = { ticks: [], written: [], heads: [], shapes: [], colourFields: [] };
  const handlers = {
    ok: function () { app.stopModalWithCode(1); },
    cancel: function () { app.stopModalWithCode(0); },
    ticked: function () {
      ui.modeBox.setEnabled(chartsEnabled(ui.ticks.map(function (t) { return t.state == 1; })));
    },
    headPicked: function (sender) {
      const colour = ui.colourFields[sender.tag];
      if (colour) colour.setStringValue(colourFor(model, sender.indexOfSelectedItem));
    },
  };
  registerClasses(handlers);
  const target = $.HbucTarget.alloc.init;
  ui.target = target; // controls hold their target weakly; ui lives as long as the window
  const width = settingsWidth(fittedWidth([labels.writtenHandbells, labels.writtenAtPitch]));
  const content = $.HbucFlippedView.alloc.initWithFrame(rect(0, 0, width, 2000));
  content.setAutoresizesSubviews(false);
  let y = MARGIN;

  // One row per instrument: chart it or not, and how its part is written (Lua cannot tell: hbuc/transpose.lua).
  addLabel(content, labels.instruments, MARGIN, y, 400, "bold");
  y += 26;
  addLabel(content, labels.chartColumn, MARGIN + 4, y, 50);
  addLabel(content, labels.instrumentColumn, MARGIN + 56, y, 220);
  addLabel(content, labels.writtenHeader, MARGIN + WRITTEN_X, y, width - 2 * MARGIN - WRITTEN_X);
  y += 22;
  const shown = Math.min(8, Math.max(3, model.instruments.length));
  const scroll = $.NSScrollView.alloc.initWithFrame(rect(MARGIN, y, width - 2 * MARGIN, shown * ROW + 4));
  scroll.setBorderType(2); // NSBezelBorder
  scroll.setHasVerticalScroller(true);
  scroll.setAutohidesScrollers(true);
  const listWidth = scroll.contentSize.width;
  const list = $.HbucFlippedView.alloc.initWithFrame(rect(0, 0, listWidth, model.instruments.length * ROW + 2));
  model.instruments.forEach(function (name, i) {
    const top = i * ROW + 2;
    const tick = addCheckbox(list, "", 16, top + 4, 22, target, "ticked:");
    tick.setState(picks.ticked[i] ? 1 : 0);
    ui.ticks.push(tick);
    addLabel(list, name, 56, top + 4, 220);
    const written = addPopup(list, [labels.writtenHandbells, labels.writtenAtPitch], WRITTEN_X, top,
      listWidth - WRITTEN_X - 20);
    written.selectItemAtIndex(picks.atPitch[i] ? 1 : 0);
    ui.written.push(written);
  });
  scroll.setDocumentView(list);
  content.addSubview(scroll);
  y += shown * ROW + 4 + 12;

  addLabel(content, labels.charts, MARGIN, y + 4, 60, "bold");
  ui.modeBox = addPopup(content, model.modes, MARGIN + 64, y, 300);
  ui.modeBox.selectItemAtIndex(Math.max(0, model.modes.indexOf(picks.mode)));
  ui.modeBox.setEnabled(chartsEnabled(picks.ticked));
  y += 34;
  ui.newPage = addCheckbox(content, labels.newPage, MARGIN, y, 400);
  ui.newPage.setState(picks.newPage ? 1 : 0);
  y += 30;

  addLabel(content, labels.noteheadHeader, 200, y, 230, "bold");
  addLabel(content, labels.shapeHeader, 440, y, 200, "bold");
  y += 24;
  model.kinds.forEach(function (k, i) {
    addLabel(content, field(k, "label"), MARGIN, y + 4, 175);
    const head = addPopup(content, model.headNames, 200, y, 230, target, "headPicked:", i);
    if (model.headNames.length > 0) head.selectItemAtIndex(picks.heads[i]);
    ui.heads.push(head);
    const shape = addPopup(content, model.shapes, 440, y, width - MARGIN - 440);
    shape.selectItemAtIndex(Math.max(0, model.shapes.indexOf(picks.shapes[i])));
    ui.shapes.push(shape);
    y += 30;
  });
  y += 8;
  model.kinds.forEach(function (k, i) {
    if (!hasColour(k)) return;
    addLabel(content, field(k, "colourLabel"), MARGIN, y + 3, 175);
    const colour = $.NSTextField.textFieldWithString(picks.colours[i]);
    colour.setFrame(rect(200, y, 120, 22));
    content.addSubview(colour);
    ui.colourFields[i] = colour;
    y += 28;
  });
  y += 6;
  ui.remove = addCheckbox(content, labels.remove, MARGIN, y, 400);
  y += 34;

  addLabel(content, labels.saveNote, MARGIN, y + 8, width - 2 * MARGIN - 210, "grey");
  addButton(content, labels.cancel, width - MARGIN - 202, y, 96, target, "cancel:", "\u001b");
  addButton(content, labels.ok, width - MARGIN - 96, y, 96, target, "ok:", "\r");
  y += 32 + MARGIN;
  content.setFrame(rect(0, 0, width, y));

  const window = $.NSWindow.alloc.initWithContentRectStyleMaskBackingDefer(rect(0, 0, width, y), 1, 2, false); // titled; buffered
  window.setTitle(model.title);
  window.setReleasedWhenClosed(false);
  window.setContentView(content);
  window.setLevel(3); // NSFloatingWindowLevel: above Dorico's windows
  window.center;
  activate(app);
  window.makeKeyAndOrderFront(null);
  window.orderFrontRegardless;
  const code = app.runModalForWindow(window);
  window.orderOut(null);
  if (code != 1) return cancelResponse(model);
  return settingsResponse(model, {
    ticked: ui.ticks.map(function (t) { return t.state == 1; }),
    atPitch: ui.written.map(function (p) { return p.indexOfSelectedItem == 1; }),
    mode: text(ObjC.unwrap(ui.modeBox.titleOfSelectedItem)),
    newPage: ui.newPage.state == 1,
    heads: ui.heads.map(function (p) { return Math.max(0, p.indexOfSelectedItem); }),
    shapes: ui.shapes.map(function (p) { return text(ObjC.unwrap(p.titleOfSelectedItem)); }),
    colours: model.kinds.map(function (_, i) {
      return ui.colourFields[i] ? text(ObjC.unwrap(ui.colourFields[i].stringValue)) : "";
    }),
    remove: ui.remove.state == 1,
  });
}

function showAlert(app, title, body, kind, ok) {
  const alert = $.NSAlert.alloc.init;
  alert.setMessageText(text(title));
  alert.setInformativeText(text(body));
  alert.setAlertStyle(kind === "error" ? 2 : kind === "warning" ? 0 : 1); // Critical, Warning, Informational
  const okButton = alert.addButtonWithTitle(text(ok) || "OK");
  alert.layout;
  // A lone button answers Return but not Escape, which closes the Windows results window: a button with no size
  // takes Escape and presses OK.
  const escape = $.NSButton.alloc.initWithFrame(rect(0, 0, 0, 0));
  escape.setKeyEquivalent("\u001b");
  escape.setTarget(okButton);
  escape.setAction("performClick:");
  alert.window.contentView.addSubview(escape);
  // An alert's window is a panel, which hides while its app isn't active, and macOS may refuse to activate a
  // background process: keep it showing, above Dorico, either way.
  alert.window.setHidesOnDeactivate(false);
  alert.window.setLevel(3); // NSFloatingWindowLevel
  activate(app);
  alert.window.orderFrontRegardless;
  alert.runModal;
}

// Returns the runModal code of the pressed button. Escape presses the cancel button.
function showChoice(app, choice) {
  const alert = $.NSAlert.alloc.init;
  alert.setMessageText(text(field(choice, "title")));
  alert.setInformativeText(text(field(choice, "text")));
  const cancelId = text(field(choice, "cancel"));
  toList(field(choice, "buttons")).forEach(function (b) {
    const button = alert.addButtonWithTitle(text(field(b, "label")));
    if (text(field(b, "id")) === cancelId) button.setKeyEquivalent("\u001b");
  });
  // kept showing above Dorico, as showAlert's is
  alert.window.setHidesOnDeactivate(false);
  alert.window.setLevel(3); // NSFloatingWindowLevel
  activate(app);
  alert.window.orderFrontRegardless;
  return alert.runModal;
}

// Text fields take Cmd-X, C, V, A and Z through the main menu's key equivalents, and an app that osascript starts
// has no menu: give it an Edit menu. An accessory app shows no menu bar, but the keys still go through it.
function installEditMenu(app) {
  const bar = $.NSMenu.alloc.init;
  const holder = $.NSMenuItem.alloc.init;
  bar.addItem(holder);
  const edit = $.NSMenu.alloc.initWithTitle("Edit");
  [["Undo", "undo:", "z"], ["Redo", "redo:", "Z"], ["Cut", "cut:", "x"], ["Copy", "copy:", "c"],
    ["Paste", "paste:", "v"], ["Select All", "selectAll:", "a"]].forEach(function (entry) {
    edit.addItemWithTitleActionKeyEquivalent(entry[0], entry[1], entry[2]);
  });
  holder.setSubmenu(edit);
  app.setMainMenu(bar);
}

/* exported run -- osascript calls it with the script's arguments */
function run(argv) {
  ObjC.import("Cocoa");
  const app = $.NSApplication.sharedApplication;
  app.setActivationPolicy(1); // NSApplicationActivationPolicyAccessory: windows, but no Dock icon
  installEditMenu(app);
  if (argv[0] === "--message") {
    const message = JSON.parse(readText(argv[1]));
    showAlert(app, field(message, "title"), field(message, "text"), text(field(message, "kind")),
      field(message, "ok"));
    return;
  }
  // This always answers, as the settings dialog does: a failure answers the cancel button.
  if (argv[0] === "--choice") {
    let choice = {};
    try {
      choice = JSON.parse(readText(argv[1]));
      writeText(argv[2], JSON.stringify(choiceResponse(choice, showChoice(app, choice))));
    } catch (error) {
      writeText(argv[2], JSON.stringify({ choice: text(field(choice, "cancel")), error: String(error) }));
    }
    return;
  }
  let model = requestModel({});
  try {
    model = requestModel(JSON.parse(readText(argv[0])));
    writeText(argv[1], JSON.stringify(showSettings(app, model)));
  } catch (error) {
    // The plug-in takes this as a cancel and logs the error.
    writeText(argv[1], JSON.stringify(cancelResponse(model, error)));
    const labels = model.labels;
    showAlert(app, labels.resultsTitle || "Handbells Used Chart",
      (labels.dialogFailed ? labels.dialogFailed + "\n\n" : "") + String(error), "error", labels.ok);
  }
}
