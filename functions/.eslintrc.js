module.exports = {
  env: {
    es6: true,
    node: true,
  },
  parserOptions: {
    "ecmaVersion": 2018,
  },
  extends: [
    "eslint:recommended",
    "google",
  ],
  rules: {
    "no-restricted-globals": ["error", "name", "length"],
    "prefer-arrow-callback": "error",
    "quotes": ["error", "double", { "allowTemplateLiterals": true }],
    "eol-last": "off",
    "max-len": ["warn", { "code": 120 }], // Allow lines up to 120 characters
    // "indent": ["error", 2], // Enforce 2 spaces for indentation
    "object-curly-spacing": ["error", "always"], // Enforce spacing inside curly braces
  },
  overrides: [
    {
      files: ["**/*.spec.*"],
      env: {
        mocha: true,
      },
      rules: {},
    },
  ],
  globals: {},
};
