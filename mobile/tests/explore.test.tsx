import {
  fireEvent,
  render,
  screen,
  userEvent,
} from "@testing-library/react-native";
import * as WebBrowser from "expo-web-browser";

import ExploreScreen from "../src/app/explore";

test("Explore expands image documentation and opens documentation in the native browser", async () => {
  const open = jest.spyOn(WebBrowser, "openBrowserAsync").mockResolvedValue({
    type: WebBrowser.WebBrowserResultType.DISMISS,
  });
  await render(<ExploreScreen />);
  expect(screen.getByText("Explore")).toBeVisible();
  await fireEvent.press(screen.getByText("Images"));
  expect(screen.getByText("@2x")).toBeVisible();
  expect(screen.getByText("@3x")).toBeVisible();
  await userEvent.press(screen.getByText("Expo documentation"));
  expect(open).toHaveBeenCalledWith("https://docs.expo.dev", {
    presentationStyle: WebBrowser.WebBrowserPresentationStyle.AUTOMATIC,
  });
});
