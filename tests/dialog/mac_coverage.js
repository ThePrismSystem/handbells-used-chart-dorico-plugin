// Merges the counts that instrument_mac.js's copies of mac.js wrote, one JSON file per osascript run, into one
// lcov report. Paths are made relative to the repository, as Codecov matches them against its files.
//   node mac_coverage.js <folder of JSON reports> <report folder>    writes <report folder>/lcov.info
const fs = require("fs");
const path = require("path");
const libCoverage = require("istanbul-lib-coverage");
const libReport = require("istanbul-lib-report");
const reports = require("istanbul-reports");

const ROOT = path.resolve(__dirname, "..", "..");
const [folder, out] = process.argv.slice(2);
const files = fs.readdirSync(folder).filter(function (name) { return name.endsWith(".json"); });
if (files.length === 0) {
  console.error("no coverage reports in " + folder);
  process.exit(1);
}
const map = libCoverage.createCoverageMap({});
files.forEach(function (name) {
  const counts = JSON.parse(fs.readFileSync(path.join(folder, name), "utf8"));
  Object.keys(counts).forEach(function (file) {
    const relative = path.relative(ROOT, file).split(path.sep).join("/");
    map.merge({ [relative]: Object.assign({}, counts[file], { path: relative }) });
  });
});
reports.create("lcovonly", { file: "lcov.info" }).execute(libReport.createContext({ dir: out, coverageMap: map }));
console.log("mac.js under osascript: " + files.length + " runs, " + map.getCoverageSummary().lines.pct + "% of lines");
