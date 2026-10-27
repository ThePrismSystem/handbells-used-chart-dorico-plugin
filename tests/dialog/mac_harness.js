// For tests/dialog/test_mac_script.py, with Node: loads dialog/mac.js without AppKit (its AppKit code runs only
// inside run()) and uses its pure parts.
//   node mac_harness.js <mac.js> respond <request.json> <response.json>   the answer to OK pressed at once
//   node mac_harness.js <mac.js> eval <expression>                        prints the expression's value as JSON
const fs = require("fs");
const vm = require("vm");

const [macJs, command, ...rest] = process.argv.slice(2);
const context = vm.createContext({});
vm.runInContext(fs.readFileSync(macJs, "utf8"), context, { filename: macJs });

if (command === "respond") {
  const [requestPath, responsePath] = rest;
  const model = context.requestModel(JSON.parse(fs.readFileSync(requestPath, "utf8")));
  fs.writeFileSync(responsePath, JSON.stringify(context.settingsResponse(model, context.initialPicks(model))));
} else if (command === "eval") {
  process.stdout.write(JSON.stringify(vm.runInContext(rest[0], context)));
} else {
  throw new Error("unknown command " + command);
}
