import {
  AuthRequest,
  CodeChallengeMethod,
  ResponseType,
} from "expo-auth-session";
import * as Linking from "expo-linking";
import * as SecureStore from "expo-secure-store";
import * as WebBrowser from "expo-web-browser";
import React, {
  createContext,
  useContext,
  useEffect,
  useRef,
  useState,
} from "react";
import { AppState, Platform } from "react-native";

import {
  Account,
  AuthService,
  clientId,
  issuer,
  redirectUri,
  resource,
} from "./core";

const iosVersion = String(Platform.Version).split(".").map(Number);
export const unsupported =
  Platform.OS === "ios" &&
  (iosVersion[0] < 17 || (iosVersion[0] === 17 && (iosVersion[1] ?? 0) < 4))
    ? "Secure HTTPS sign-in requires iOS 17.4 or later."
    : null;
const service = new AuthService(
  {
    get: (key) => SecureStore.getItemAsync(key),
    set: (key, value) => SecureStore.setItemAsync(key, value),
    remove: (key) => SecureStore.deleteItemAsync(key),
  },
  clientId,
);
type Auth = {
  account: Account | null;
  busy: boolean;
  message: string | null;
  signIn(): Promise<void>;
  signOut(): Promise<void>;
};
const Context = createContext<Auth>(null!);
export const useAuth = () => useContext(Context);

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [account, setAccount] = useState<Account | null>(null);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const generation = useRef(0);
  useEffect(() => {
    if (unsupported) return;
    let active = true;
    const verify = async (url?: string | null) => {
      const current = ++generation.current;
      try {
        if (url && new URL(url).pathname === "/oauth/callback")
          await service.callback(url);
        const next = await service.account();
        if (active && current === generation.current) {
          setAccount(next);
          if (next) setMessage(null);
        }
      } catch (error) {
        if (active && current === generation.current) {
          setAccount(null);
          setMessage(
            error instanceof Error ? error.message : "Sign-in failed.",
          );
        }
      }
    };
    void Linking.getInitialURL().then((url) => verify(url));
    const links = Linking.addEventListener("url", (event) => {
      void verify(event.url);
    });
    const state = AppState.addEventListener("change", (value) => {
      if (value === "active") void verify();
      else {
        generation.current++;
        setAccount(null);
      }
    });
    // Identity is never trusted indefinitely, even while the app stays foregrounded.
    const timer = setInterval(() => {
      void verify();
    }, 60_000);
    return () => {
      active = false;
      links.remove();
      state.remove();
      clearInterval(timer);
    };
  }, []);
  const signIn = async () => {
    if (unsupported || busy) return;
    setBusy(true);
    setMessage(null);
    setAccount(null);
    try {
      const request = new AuthRequest({
        clientId,
        redirectUri,
        responseType: ResponseType.Code,
        usePKCE: true,
        codeChallengeMethod: CodeChallengeMethod.S256,
        scopes: [
          "profile:read",
          "aliases:read",
          "aliases:create",
          "aliases:edit",
          "aliases:delete",
          "domains:read",
        ],
        extraParams: { resource },
      });
      const url = await request.makeAuthUrlAsync({
        authorizationEndpoint: `${issuer}/oauth/authorize`,
      });
      if (!request.codeVerifier)
        throw new Error("Unable to create PKCE transaction.");
      await service.savePending({
        state: request.state,
        verifier: request.codeVerifier,
        clientId,
        created: Date.now(),
      });
      const result = await WebBrowser.openAuthSessionAsync(url, redirectUri, {
        preferUniversalLinks: true,
      });
      if (result.type === "success") await service.callback(result.url);
      // Android can report dismissal before delivering the HTTPS Linking callback.
      else if (Platform.OS !== "android" || result.type !== "dismiss") {
        await service.cancelPending();
        setMessage("Sign-in cancelled. You can try again.");
      }
      setAccount(await service.account());
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Sign-in failed.");
    } finally {
      setBusy(false);
    }
  };
  const signOut = async () => {
    generation.current++;
    setBusy(true);
    setAccount(null);
    setMessage(null);
    try {
      await service.logout();
    } catch (error) {
      setMessage(
        error instanceof Error ? error.message : "Unable to revoke connection.",
      );
    } finally {
      setBusy(false);
    }
  };
  return (
    <Context.Provider value={{ account, busy, message, signIn, signOut }}>
      {children}
    </Context.Provider>
  );
}
