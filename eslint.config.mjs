import js from "@eslint/js";
import globals from "globals";

export default [
  js.configs.recommended,
  {
    // The Mac dialog: JavaScript for Automation, which osascript runs as a script with the Objective-C bridge.
    files: ["plugin/**/*.js"],
    languageOptions: {
      ecmaVersion: 2022,
      sourceType: "script",
      globals: { ObjC: "readonly", $: "readonly", Application: "readonly", Path: "readonly" },
    },
  },
  {
    files: ["tests/**/*.js"],
    languageOptions: {
      ecmaVersion: 2022,
      sourceType: "commonjs",
      globals: globals.node,
    },
  },
];
