module.exports = {
  env: {
    es6: true,
    node: true,
  },
  parserOptions: {
    "ecmaVersion": 2022, // Use the latest ECMAScript version
    "sourceType": "module", // Enable ECMAScript modules
    "ecmaFeatures": {
      "globalReturn": true, // Allow return statements in the global scope
      "impliedStrict": true, // Enable strict mode automatically
    },
    "allowImportExportEverywhere": true, // Allow import/export statements anywhere
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
    "linebreak-style": ["error", "unix"], // Explicitly set to LF
    "max-len": ["warn", { "code": 180 }], // Allow lines up to 120 characters
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
