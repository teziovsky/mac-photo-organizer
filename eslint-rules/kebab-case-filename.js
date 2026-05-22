/** @typedef {import("eslint").Rule.RuleModule} RuleModule */

const KEBAB_CASE = /^[a-z][a-z0-9]*(-[a-z0-9]+)*(\.test)?$/;

/**
 * @param {string} filename
 * @returns {boolean}
 */
function isKebabCase(filename) {
  return KEBAB_CASE.test(filename);
}

/** @type {RuleModule} */
module.exports = {
  meta: {
    type: "suggestion",
    docs: {
      description: "Require source file names to use kebab-case",
    },
    schema: [],
    messages: {
      notKebabCase: 'Filename "{{name}}" must be kebab-case (e.g. my-component.tsx).',
    },
  },
  create(context) {
    const filename = context.filename;
    const basename = filename.split(/[/\\]/).pop() ?? "";
    const nameWithoutExt = basename.replace(/\.(tsx?|jsx?)$/, "");

    if (!isKebabCase(nameWithoutExt)) {
      context.report({
        loc: { line: 1, column: 0 },
        messageId: "notKebabCase",
        data: { name: basename },
      });
    }

    return {};
  },
};
