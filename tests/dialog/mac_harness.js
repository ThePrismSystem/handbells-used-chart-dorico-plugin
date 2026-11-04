// For tests/dialog/test_mac_script.py and test_mac_coverage.py, with Node: loads dialog/mac.js without AppKit (its
// AppKit code runs only inside run()) and uses its pure parts.
//   node mac_harness.js <mac.js> respond <request.json> <response.json>   the answer to OK pressed at once
//   node mac_harness.js <mac.js> eval <expression>                        prints the expression's value as JSON
//   node mac_harness.js <mac.js> jxa-run [argv...]                        run(argv), which throws at its first AppKit call
// With HBUC_JS_COVERAGE set to a folder, a script of the plug-in counts its statements as instrument_mac.js's copy
// does under osascript, and the counts go into the folder when Node exits (python tools/run_tests.py --coverage).
const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const [macJs, command, ...rest] = process.argv.slice(2);
const file = path.resolve(macJs);
const reports = process.env.HBUC_JS_COVERAGE;
const measured = Boolean(reports) && file.startsWith(path.resolve(__dirname, "..", "..", "plugin") + path.sep);
const context = vm.createContext({});
let source = fs.readFileSync(file, "utf8");
if (measured) {
  source = require("./instrument_mac.js").instrument(source, file);
  process.on("exit", function () {
    fs.writeFileSync(path.join(reports, "coverage-" + crypto.randomUUID() + ".json"), JSON.stringify(context.__coverage__));
  });
}
vm.runInContext(source, context, { filename: file });

// Stand-ins for the parts of osascript's Objective-C bridge that instrument_mac.js's wrapper uses, so an
// instrumented copy's run() can be tried here.
function bridge() {
  const $ = function (value) {
    return { writeToFileAtomicallyEncodingError: function (path) { fs.writeFileSync(path, value); return true; } };
  };
  $.NSProcessInfo = { processInfo: { environment: { objectForKey: function (name) { return process.env[name]; } } } };
  return {
    $: $,
    ObjC: {
      import: function (name) { if (name !== "Foundation") throw new Error("no AppKit under Node: " + name); },
      unwrap: function (value) { return value; },
    },
  };
}

if (command === "jxa-run") {
  Object.assign(context, bridge());
  context.run(rest);
} else if (command === "respond") {
  const [requestPath, responsePath] = rest;
  const model = context.requestModel(JSON.parse(fs.readFileSync(requestPath, "utf8")));
  fs.writeFileSync(responsePath, JSON.stringify(context.settingsResponse(model, context.initialPicks(model))));
} else if (command === "eval") {
  process.stdout.write(JSON.stringify(vm.runInContext(rest[0], context)));
} else {
  throw new Error("unknown command " + command);
}
