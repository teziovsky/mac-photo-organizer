/** @typedef {import("eslint").Rule.RuleModule} RuleModule */

const { CONSOLE_TO_DEV } = require("./console-methods");

const DEV_LOG_IMPORT = "@/utils/dev-log";

/**
 * @param {import("estree").CallExpression} node
 * @returns {string | null}
 */
function getConsoleMethod(node) {
  const { callee } = node;
  if (callee.type !== "MemberExpression") return null;
  if (callee.computed || callee.optional) return null;

  const { object, property } = callee;
  if (object.type !== "Identifier" || object.name !== "console") return null;
  if (property.type !== "Identifier") return null;

  return CONSOLE_TO_DEV[property.name] ? property.name : null;
}

/**
 * @param {import("estree").Node} node
 * @param {(n: import("estree").Node) => void} visit
 */
function walkNode(node, visit) {
  if (!node || typeof node !== "object") return;
  visit(node);
  for (const key of Object.keys(node)) {
    if (key === "parent") continue;
    const child = node[key];
    if (Array.isArray(child)) {
      for (const item of child) {
        if (item && typeof item.type === "string") walkNode(item, visit);
      }
    } else if (child && typeof child.type === "string") {
      walkNode(child, visit);
    }
  }
}

/**
 * @param {import("eslint").SourceCode} sourceCode
 * @returns {Set<string>}
 */
function collectDevSymbolsInFile(sourceCode) {
  const symbols = new Set();

  walkNode(sourceCode.ast, node => {
    if (node.type !== "CallExpression") return;
    const method = getConsoleMethod(node);
    if (method) symbols.add(CONSOLE_TO_DEV[method]);
  });

  return symbols;
}

/**
 * @param {import("eslint").SourceCode} sourceCode
 * @returns {import("estree").ImportDeclaration | null}
 */
function getLastImportDeclaration(sourceCode) {
  let last = null;
  for (const node of sourceCode.ast.body) {
    if (node.type !== "ImportDeclaration") break;
    last = node;
  }
  return last;
}

/**
 * @param {import("eslint").SourceCode} sourceCode
 * @returns {{ declaration: import("estree").ImportDeclaration | null; imported: Set<string> }}
 */
function findDevLogImport(sourceCode) {
  const imported = new Set();
  let declaration = null;

  for (const node of sourceCode.ast.body) {
    if (node.type !== "ImportDeclaration" || node.source.value !== DEV_LOG_IMPORT) continue;
    declaration = node;
    for (const specifier of node.specifiers) {
      if (specifier.type === "ImportSpecifier") {
        imported.add(specifier.imported.name);
      }
    }
  }

  return { declaration, imported };
}

/**
 * @param {import("eslint").Rule.RuleFixer} fixer
 * @param {import("eslint").SourceCode} sourceCode
 * @param {Set<string>} neededSymbols
 * @returns {import("eslint").Rule.Fix[]}
 */
function ensureDevLogImport(fixer, sourceCode, neededSymbols) {
  const { declaration, imported } = findDevLogImport(sourceCode);
  const missing = [...neededSymbols].filter(symbol => !imported.has(symbol)).sort();

  if (missing.length === 0) return [];

  if (declaration) {
    const lastSpecifier = declaration.specifiers.at(-1);
    if (!lastSpecifier) return [];
    return [fixer.insertTextAfter(lastSpecifier, `, ${missing.join(", ")}`)];
  }

  const importLine = `import { ${[...neededSymbols].sort().join(", ")} } from "${DEV_LOG_IMPORT}";\n`;
  const lastImport = getLastImportDeclaration(sourceCode);

  if (lastImport) {
    return [fixer.insertTextAfter(lastImport, `\n${importLine.trimEnd()}`)];
  }

  const firstStatement = sourceCode.ast.body[0];
  if (firstStatement) {
    return [fixer.insertTextBefore(firstStatement, importLine)];
  }

  return [fixer.insertTextAfterRange([0, 0], importLine)];
}

/** @type {RuleModule} */
module.exports = {
  meta: {
    type: "suggestion",
    docs: {
      description: "Replace console.* calls with dev-only helpers from @/utils/dev-log",
    },
    fixable: "code",
    schema: [],
    messages: {
      useDevLog: "Use {{devName}} from @/utils/dev-log instead of console.{{method}}.",
    },
  },
  create(context) {
    const sourceCode = context.sourceCode;

    return {
      CallExpression(node) {
        const method = getConsoleMethod(node);
        if (!method) return;

        const devName = CONSOLE_TO_DEV[method];

        context.report({
          node: node.callee,
          messageId: "useDevLog",
          data: { method, devName },
          fix(fixer) {
            const neededSymbols = collectDevSymbolsInFile(sourceCode);

            return [fixer.replaceText(node.callee, devName), ...ensureDevLogImport(fixer, sourceCode, neededSymbols)];
          },
        });
      },
    };
  },
};
