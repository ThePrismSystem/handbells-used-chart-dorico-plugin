// For tests/dialog/test_mac_dialog.py: works dialog/mac.js's windows through System Events, as a person would. The
// process running osascript needs the Accessibility permission, which GitHub's macOS runners grant.
//   osascript -l JavaScript mac_drive.js <pid> wait                  prints the front window's title
//   osascript -l JavaScript mac_drive.js <pid> press <title>         clicks the button with that title
//   osascript -l JavaScript mac_drive.js <pid> key <return|escape>   brings the process forward and types the key
//   osascript -l JavaScript mac_drive.js <pid> tick <row>            clicks the checkbox in that row of the list
//   osascript -l JavaScript mac_drive.js <pid> pick <popup> <item>   chooses an item from a pop-up button
//   osascript -l JavaScript mac_drive.js <pid> dump                  prints the front window's controls as JSON
// Rows, pop-ups and items count from 0, pop-ups in the window's order. Each action waits up to 30 s for what it
// needs and exits with an error when it doesn't appear.

const WAIT_MS = 30000;
const KEY_CODES = { return: 36, escape: 53 };

function attempt(fn, fallback) {
  try {
    return fn();
  } catch {
    return fallback;
  }
}

// fn's first answer that isn't null, retried until the wait is over.
function until(what, fn) {
  const deadline = Date.now() + WAIT_MS;
  for (;;) {
    const value = attempt(fn, null);
    if (value !== null) return value;
    if (Date.now() > deadline) throw new Error(what + " did not appear within " + WAIT_MS / 1000 + " s");
    delay(0.25);
  }
}

function controls(element, role) {
  return element.entireContents().filter(function (e) { return attempt(function () { return e.role(); }, "") === role; });
}

function describe(window) {
  ObjC.import("AppKit");
  const screen = $.NSScreen.mainScreen.frame.size;
  const read = function (e, name) { return attempt(function () { return e[name](); }, null); };
  return JSON.stringify({
    title: read(window, "name"),
    position: read(window, "position"),
    size: read(window, "size"),
    screen: [screen.width, screen.height],
    buttons: controls(window, "AXButton").map(function (e) {
      return { title: read(e, "title"), enabled: read(e, "enabled") };
    }),
    checkboxes: controls(window, "AXCheckBox").map(function (e) {
      return { title: read(e, "title"), value: read(e, "value") };
    }),
    popups: controls(window, "AXPopUpButton").map(function (e) {
      return { value: read(e, "value"), enabled: read(e, "enabled") };
    }),
    fields: controls(window, "AXTextField").map(function (e) { return read(e, "value"); }),
    texts: controls(window, "AXStaticText").map(function (e) { return read(e, "value"); }),
  });
}

/* exported run -- osascript calls it with the script's arguments */
function run(argv) {
  const pid = Number(argv[0]);
  const action = argv[1];
  const se = Application("System Events");
  const proc = until("process " + pid, function () { return se.processes.whose({ unixId: pid })()[0] || null; });
  const window = until("a window of process " + pid, function () { return proc.windows().length > 0 ? proc.windows[0] : null; });
  if (action === "wait") return attempt(function () { return window.name(); }, "");
  if (action === "dump") return describe(window);
  if (action === "press") {
    until("the " + argv[2] + " button", function () {
      const found = controls(window, "AXButton").filter(function (b) { return b.title() === argv[2]; });
      return found.length > 0 ? found[0] : null;
    }).click();
  } else if (action === "key") {
    if (!(argv[2] in KEY_CODES)) throw new Error("unknown key " + argv[2]);
    proc.frontmost = true;
    delay(0.5);
    se.keyCode(KEY_CODES[argv[2]]);
  } else if (action === "tick") {
    until("row " + argv[2], function () {
      return controls(window.scrollAreas[0], "AXCheckBox")[Number(argv[2])] || null;
    }).click();
  } else if (action === "pick") {
    const popup = until("pop-up " + argv[2], function () {
      return controls(window, "AXPopUpButton")[Number(argv[2])] || null;
    });
    popup.click();
    until("item " + argv[3] + " of pop-up " + argv[2], function () {
      return popup.menus[0].menuItems()[Number(argv[3])] || null;
    }).click();
  } else {
    throw new Error("unknown action " + action);
  }
  return "";
}
