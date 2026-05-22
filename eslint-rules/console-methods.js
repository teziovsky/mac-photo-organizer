/** Console methods supported by @/utils/dev-log (console.X -> devX). */
const CONSOLE_METHODS = [
  "log",
  "warn",
  "error",
  "debug",
  "info",
  "table",
  "dir",
  "trace",
  "group",
  "groupCollapsed",
  "groupEnd",
  "time",
  "timeEnd",
  "timeLog",
  "assert",
];

/** @param {string} method */
function toDevConsoleName(method) {
  return `dev${method.charAt(0).toUpperCase()}${method.slice(1)}`;
}

/** @type {Record<string, string>} */
const CONSOLE_TO_DEV = Object.fromEntries(CONSOLE_METHODS.map(method => [method, toDevConsoleName(method)]));

module.exports = {
  CONSOLE_METHODS,
  toDevConsoleName,
  CONSOLE_TO_DEV,
};
