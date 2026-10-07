jest.mock("react-native-worklets", () =>
  require("react-native-worklets/src/mock"),
);
jest.mock("react-native-reanimated", () =>
  require("react-native-reanimated/mock"),
);
jest.mock(
  "react-native-safe-area-context",
  () => require("react-native-safe-area-context/jest/mock").default,
);
