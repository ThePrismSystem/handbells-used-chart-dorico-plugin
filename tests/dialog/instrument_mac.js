// Makes a copy of dialog/mac.js that counts its own statements, for tests/dialog/test_mac_dialog.py when
// HBUC_JS_COVERAGE is set. osascript runs the copy as it runs mac.js. When run() returns or throws, the copy writes
// its counts as istanbul JSON to the file named by $HBUC_COVERAGE, and mac_coverage.js merges them.
//   node instrument_mac.js <mac.js> <copy.js>
// mac_harness.js counts its Node runs of mac.js with the same instrument(), so both report the same lines.
const fs = require("fs");
const path = require("path");
const { createInstrumenter } = require("istanbul-lib-instrument");

// The script's source with counters added. JXA has no globalThis, and "this" at the top of a script is its global
// object, where the counts are kept as __coverage__.
function instrument(source, file) {
  return createInstrumenter({ esModules: false, coverageGlobalScope: "this", coverageGlobalScopeFunc: true })
    .instrumentSync(source, file);
}

function main(source, copy) {
  const file = path.resolve(source);
  let code = instrument(fs.readFileSync(file, "utf8"), file);
  if (!/function run\(argv\)/.test(code)) throw new Error("run(argv) not found in " + file);
  code = code.replace(/function run\(argv\)/, "function hbucMeasuredRun(argv)");
  code += `
function run(argv) {
  try {
    return hbucMeasuredRun(argv);
  } finally {
    ObjC.import("Foundation");
    const report = ObjC.unwrap($.NSProcessInfo.processInfo.environment.objectForKey("HBUC_COVERAGE"));
    const counts = (new Function("return this"))().__coverage__;
    $(JSON.stringify(counts)).writeToFileAtomicallyEncodingError(report, true, 4, null); // NSUTF8StringEncoding
  }
}
`;
  fs.writeFileSync(copy, code);
}

if (require.main === module) main(...process.argv.slice(2));

module.exports = { instrument };
