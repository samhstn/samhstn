module.exports = {
  extends: [
    "eslint:recommended"
  ],
  parserOptions: {
    ecmaVersion: 2017
  },
  env: {
    node: true,
    es6: true
  },
  rules: {
    semi: ["error", "always"]
  }
}
