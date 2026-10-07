import { act, fireEvent, render, screen } from "@testing-library/react-native";
import * as Linking from "expo-linking";
import * as SecureStore from "expo-secure-store";
import * as WebBrowser from "expo-web-browser";
import { AppState, AppStateStatus, Platform } from "react-native";
import { createHash } from "node:crypto";

Platform.OS = "android";
const transport = jest.fn();
jest.spyOn(globalThis, "fetch").mockImplementation(transport);
const { AuthProvider } = require("../src/auth/context");
const HomeScreen = require("../src/app/index").default;

jest.mock("expo-crypto", () => ({
  ...jest.requireActual("expo-crypto"),
  getRandomValues: (array: Uint8Array) =>
    require("node:crypto").webcrypto.getRandomValues(array),
  digestStringAsync: async (
    _algorithm: string,
    value: string,
    options: { encoding: string },
  ) =>
    require("node:crypto")
      .createHash("sha256")
      .update(value)
      .digest(options.encoding),
}));

let callback: string;
let authorization: URL;
let link: (event: { url: string }) => void;
let appState: (state: AppStateStatus) => void;
let completeBrowser: (result: WebBrowser.WebBrowserAuthSessionResult) => void;
let removeLink: jest.SpyInstance;
let removeState: jest.Mock;
const addLinkListener = Linking.addEventListener;

beforeEach(() => {
  Platform.OS = "android";
  jest.useFakeTimers();
  const storage = new Map<string, string>();
  jest
    .spyOn(SecureStore, "getItemAsync")
    .mockImplementation(async (key) => storage.get(key) ?? null);
  jest
    .spyOn(SecureStore, "setItemAsync")
    .mockImplementation(async (key, value) => {
      storage.set(key, value);
    });
  jest.spyOn(SecureStore, "deleteItemAsync").mockImplementation(async (key) => {
    storage.delete(key);
  });
  jest.spyOn(Linking, "getInitialURL").mockResolvedValue(null);
  removeState = jest.fn();
  jest
    .spyOn(Linking, "addEventListener")
    .mockImplementation((_event, handler) => {
      link = handler;
      const subscription = addLinkListener(_event, handler);
      removeLink = jest.spyOn(subscription, "remove");
      return subscription;
    });
  jest
    .spyOn(AppState, "addEventListener")
    .mockImplementation((_event, handler) => {
      appState = handler;
      return { remove: removeState };
    });
  jest.spyOn(WebBrowser, "openAuthSessionAsync").mockImplementation((url) => {
    authorization = new URL(url);
    callback = `https://app.shroud.email/oauth/callback?${new URLSearchParams({
      state: authorization.searchParams.get("state")!,
      iss: "https://app.shroud.email",
      code: "code",
    })}`;
    return new Promise((resolve) => {
      completeBrowser = resolve;
    });
  });
  transport.mockReset().mockImplementation(async (url: string) => {
    if (url.endsWith("/oauth/token"))
      return Response.json({
        access_token: "access",
        refresh_token: "refresh",
        token_type: "Bearer",
        expires_in: 3600,
        resource: "https://app.shroud.email/api/v1",
      });
    if (url.endsWith("/oauth/revoke"))
      return new Response(null, { status: 200 });
    return Response.json({ email: "person@example.com" });
  });
});

afterEach(() => {
  jest.restoreAllMocks();
  jest.useRealTimers();
});

async function openSignIn() {
  await render(
    <AuthProvider>
      <HomeScreen />
    </AuthProvider>,
  );
  await fireEvent.press(screen.getByRole("button", { name: /^sign in$/i }));
  expect(screen.getByRole("button", { name: /please wait/i })).toBeDisabled();
  expect(WebBrowser.openAuthSessionAsync).toHaveBeenCalled();
}

async function browser(result: WebBrowser.WebBrowserAuthSessionResult) {
  await act(async () => {
    completeBrowser(result);
  });
}

function exchanges() {
  return transport.mock.calls.filter(([url]) => url.endsWith("/oauth/token"));
}

test("sign-in sends the registered client, callback, resource, and matching PKCE proof", async () => {
  await openSignIn();
  expect(authorization.origin + authorization.pathname).toBe(
    "https://app.shroud.email/oauth/authorize",
  );
  expect(authorization.searchParams.get("client_id")).toBe(
    "3dab4011-1a87-453f-9b6d-c8e12a41c892",
  );
  expect(authorization.searchParams.get("redirect_uri")).toBe(
    "https://app.shroud.email/oauth/callback",
  );
  expect(authorization.searchParams.get("resource")).toBe(
    "https://app.shroud.email/api/v1",
  );
  expect(authorization.searchParams.get("code_challenge_method")).toBe("S256");
  await browser({ type: "success", url: callback });
  const body = new URLSearchParams(exchanges()[0][1].body);
  expect(body.get("client_id")).toBe("3dab4011-1a87-453f-9b6d-c8e12a41c892");
  expect(body.get("redirect_uri")).toBe(
    "https://app.shroud.email/oauth/callback",
  );
  expect(body.get("resource")).toBe("https://app.shroud.email/api/v1");
  expect(body.get("grant_type")).toBe("authorization_code");
  expect(
    createHash("sha256").update(body.get("code_verifier")!).digest("base64url"),
  ).toBe(authorization.searchParams.get("code_challenge"));
  expect(screen.getByText("Signed in as person@example.com")).toBeVisible();
});

test("Android dismissal still accepts the later app callback", async () => {
  await openSignIn();
  await act(async () => {
    appState("active");
  });
  await browser({ type: WebBrowser.WebBrowserResultType.DISMISS });
  expect(screen.queryByText(/cancelled/)).toBeNull();
  await act(async () => {
    link({ url: callback });
  });
  expect(screen.getByText("Signed in as person@example.com")).toBeVisible();
  expect(exchanges()).toHaveLength(1);
});

test.each(["dismiss", "success"] as const)(
  "app callback before browser %s signs in exactly once",
  async (result) => {
    await openSignIn();
    await act(async () => {
      link({ url: callback });
    });
    await browser(
      result === "success"
        ? { type: result, url: callback }
        : { type: WebBrowser.WebBrowserResultType.DISMISS },
    );
    expect(screen.getByText("Signed in as person@example.com")).toBeVisible();
    expect(screen.getByRole("button", { name: /^sign out$/i })).toBeEnabled();
    expect(screen.queryByText(/cancelled/)).toBeNull();
    expect(exchanges()).toHaveLength(1);
  },
);

test.each([
  ["android", WebBrowser.WebBrowserResultType.CANCEL],
  ["ios", WebBrowser.WebBrowserResultType.DISMISS],
] as const)(
  "%s cancellation rejects a late callback",
  async (platform, result) => {
    Platform.OS = platform;
    await openSignIn();
    await browser({ type: result });
    await act(async () => {
      link({ url: callback });
    });
    expect(screen.getByText(/Sign-in cancelled/)).toBeVisible();
    expect(screen.getByRole("button", { name: /^sign in$/i })).toBeEnabled();
    expect(screen.queryByText(/Signed in as/)).toBeNull();
    expect(exchanges()).toHaveLength(0);
  },
);

test("periodic verification retains identity while pending, hides it on failure, and recovers", async () => {
  await openSignIn();
  await browser({ type: "success", url: callback });
  let completeVerification!: (response: Response) => void;
  transport.mockImplementationOnce(
    () =>
      new Promise((resolve) => {
        completeVerification = resolve;
      }),
  );
  await act(async () => {
    jest.advanceTimersByTime(60_000);
  });
  expect(screen.getByText("Signed in as person@example.com")).toBeVisible();
  await act(async () => {
    completeVerification(Response.json({ email: "person@example.com" }));
  });
  expect(screen.getByText("Signed in as person@example.com")).toBeVisible();
  transport.mockResolvedValueOnce(new Response("{}", { status: 500 }));
  await act(async () => {
    jest.advanceTimersByTime(60_000);
  });
  expect(screen.queryByText(/Signed in as/)).toBeNull();
  expect(screen.getByText(/Unable to verify/)).toBeVisible();
  await act(async () => {
    jest.advanceTimersByTime(60_000);
  });
  expect(screen.getByText("Signed in as person@example.com")).toBeVisible();
  expect(screen.queryByText(/Unable to verify/)).toBeNull();
});

test("sign-out clears the displayed identity even when revocation is offline", async () => {
  await openSignIn();
  await browser({ type: "success", url: callback });
  transport.mockRejectedValueOnce(new Error("offline"));
  await fireEvent.press(screen.getByRole("button", { name: /^sign out$/i }));
  expect(screen.queryByText(/Signed in as/)).toBeNull();
  expect(screen.getByText(/Signed out locally/)).toBeVisible();
  await act(async () => {
    appState("active");
  });
  expect(screen.queryByText(/Signed in as/)).toBeNull();
});

test("unmount removes native subscriptions and stops periodic network verification", async () => {
  await openSignIn();
  await browser({ type: "success", url: callback });
  await screen.unmount();
  expect(removeLink).toHaveBeenCalledTimes(1);
  expect(removeState).toHaveBeenCalledTimes(1);
  transport.mockClear();
  await act(async () => {
    jest.advanceTimersByTime(120_000);
  });
  expect(transport).not.toHaveBeenCalled();
});

test("an in-flight verification cannot restore the identity after sign-out", async () => {
  await openSignIn();
  await browser({ type: "success", url: callback });
  let completeVerification!: (response: Response) => void;
  transport.mockImplementationOnce(
    () =>
      new Promise((resolve) => {
        completeVerification = resolve;
      }),
  );
  await act(async () => {
    appState("active");
  });
  await fireEvent.press(screen.getByRole("button", { name: /^sign out$/i }));
  expect(screen.queryByText(/Signed in as/)).toBeNull();
  await act(async () => {
    completeVerification(Response.json({ email: "person@example.com" }));
  });
  expect(screen.queryByText(/Signed in as/)).toBeNull();
  expect(screen.getByRole("button", { name: /^sign in$/i })).toBeEnabled();
});
