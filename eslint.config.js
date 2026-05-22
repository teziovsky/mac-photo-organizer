const { defineConfig } = require("eslint/config");
const raycastConfig = require("@raycast/eslint-config");
const localRules = require("./eslint-rules");

module.exports = defineConfig([
  {
    ignores: ["raycast-env.d.ts"],
  },
  ...raycastConfig,
  {
    files: ["eslint.config.js", "eslint-rules/**/*.js"],
    rules: {
      "@typescript-eslint/no-require-imports": "off",
    },
  },
  {
    files: ["src/**/*.{ts,tsx}"],
    ignores: ["src/utils/dev-log.ts", "src/utils/run-apple-script.ts"],
    plugins: {
      local: localRules,
    },
    rules: {
      "local/console-to-dev-log": "error",
      "local/kebab-case-filename": "error",
      "no-console": "off",
      "no-restricted-imports": [
        "error",
        {
          patterns: [
            {
              group: ["./*", "./**", "../*", "../**"],
              message: "Use the @/ path alias instead of relative imports.",
            },
          ],
        },
      ],
      "@typescript-eslint/no-unused-vars": [
        "error",
        {
          argsIgnorePattern: "^_",
          varsIgnorePattern: "^_",
        },
      ],
    },
  },
]);
