module.exports = {
	env: {
		browser: true,
		es6: true,
	},
	parser: "@typescript-eslint/parser",
	parserOptions: {
		sourceType: "module",
		ecmaFeatures: {
			jsx: true,
		},
	},
	settings: {},
	plugins: ["eslint-plugin-jsdoc", "@typescript-eslint"],
	extends: [
		// ...
	],
	rules: {
		"@typescript-eslint/explicit-member-accessibility": [
			"error",
			{
				accessibility: "explicit",
				overrides: {
					accessors: "explicit",
					constructors: "off",
				},
			},
		],
		"@typescript-eslint/indent": ["error", "tab"],
		"@typescript-eslint/member-delimiter-style": [
			"error",
			{
				multiline: {
					delimiter: "semi",
					requireLast: true,
				},
				singleline: {
					delimiter: "semi",
					requireLast: false,
				},
			},
		],
		// "@typescript-eslint/naming-convention": "error",
		"@typescript-eslint/no-unnecessary-boolean-literal-compare": "off",
		"@typescript-eslint/quotes": ["error", "double"],
		"@typescript-eslint/semi": ["error", "always"],
		"@typescript-eslint/type-annotation-spacing": "error",
		eqeqeq: ["error", "smart"],
		"id-blacklist": [
			"error",
			"any",
			"Number",
			"number",
			"String",
			"string",
			"Boolean",
			"boolean",
			"Undefined",
			"undefined",
		],
		"id-match": "error",
		"jsdoc/check-indentation": ["warn", { excludeTags: ["apiExample", "apiErrorExample"]}],
		"jsdoc/newline-after-description": "error",
		"new-parens": "error",
		"no-eval": "error",
		"no-trailing-spaces": "error",
		"no-underscore-dangle": "off",
		"no-unsafe-finally": "error",
		"no-var": "error",
		radix: "error",
		"brace-style": ["error", "1tbs"],
		"keyword-spacing": ["error", { after: true }],
		"semi-style": ["error", "last"],
		"spaced-comment": [
			"error",
			"always",
			{
				markers: ["/"],
			},
		],
	},
};
