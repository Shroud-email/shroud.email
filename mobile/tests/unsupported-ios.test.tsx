import {
  fireEvent,
  render,
  screen,
  waitFor,
} from "@testing-library/react-native";
import * as SecureStore from "expo-secure-store";
import { Platform } from "react-native";

Platform.OS = "ios";
Object.defineProperty(Platform, "Version", {
  value: "17.3",
  configurable: true,
});
const { AuthProvider } = require("../src/auth/context");
const HomeScreen = require("../src/app/index").default;

afterEach(() => jest.restoreAllMocks());

test("unsupported iOS disables sign-in but allows local session cleanup", async () => {
  const remove = jest.spyOn(SecureStore, "deleteItemAsync").mockResolvedValue();
  jest.spyOn(SecureStore, "getItemAsync").mockResolvedValue(null);
  await render(
    <AuthProvider>
      <HomeScreen />
    </AuthProvider>,
  );
  expect(
    screen.getByText("Secure HTTPS sign-in requires iOS 17.4 or later."),
  ).toBeVisible();
  expect(screen.getByRole("button", { name: "Sign in" })).toBeDisabled();
  const cleanup = screen.getByRole("button", {
    name: "Clear session / sign out",
  });
  expect(cleanup).toBeEnabled();
  await fireEvent.press(cleanup);
  await waitFor(() => expect(remove).toHaveBeenCalled());
});
