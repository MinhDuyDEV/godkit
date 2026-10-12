"use strict";
// Preloaded into seatwork's run.cjs (node --require): when run.cjs asks for ./cases.cjs it gets
// seatwork's cases followed by the godkit cases. Seatwork's files stay untouched.
const Module = require("node:module");
const path = require("node:path");

const original = Module.prototype.require;
Module.prototype.require = function (id) {
  const loaded = original.apply(this, arguments);
  if (id === "./cases.cjs" && this.filename && path.basename(this.filename) === "run.cjs") {
    process.env.SLP_EVALS_DIR = path.dirname(this.filename);
    const godkit = original.call(this, path.join(__dirname, "cases-godkit.cjs"));
    const known = new Set(loaded.map((c) => c.name));
    return [...loaded, ...godkit.filter((c) => !known.has(c.name))];
  }
  return loaded;
};
