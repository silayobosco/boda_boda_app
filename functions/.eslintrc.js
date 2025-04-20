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
    "eol-last": 0,
    "no-multiple-empty-lines": ["error", {"max": 1, "maxEOF": 0}],
    "linebreak-style": ["error", "unix"],
    "max-len": ["error", 80],
    "require-jsdoc": "error",
    "arrow-parens": ["error", "always"],
    "comma-dangle": ["error", "always-multiline"],
    "object-curly-spacing": ["error", "never"],
    "no-restricted-globals": ["error", "name", "length"],
    "prefer-arrow-callback": "error",
    "quotes": ["error", "double", {"allowTemplateLiterals": true}],
  },
  overrides: [
    {
      files: ["**/*.spec.*"],
      env: {
        mocha: true,
      },
      rules: {
        "quotes": ["error", "double"],
        "linebreak-style": ["error", "unix"],
        "max-len": ["error", 80],
        "require-jsdoc": "error",
        "arrow-parens": ["error", "always"],
        "comma-dangle": ["error", "always-multiline"],
        "object-curly-spacing": ["error", "never"],
      },
    },
  ],
  globals: {},
};
