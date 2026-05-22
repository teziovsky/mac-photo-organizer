const consoleToDevLog = require("./console-to-dev-log");
const kebabCaseFilename = require("./kebab-case-filename");

module.exports = {
  rules: {
    "console-to-dev-log": consoleToDevLog,
    "kebab-case-filename": kebabCaseFilename,
  },
};
