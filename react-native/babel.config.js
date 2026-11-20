// Applies to the package source in `..` too, so its `codegenNativeComponent` specs are transformed.
module.exports = (api) => {
  api.cache(true);
  return { presets: ["babel-preset-expo"] };
};
