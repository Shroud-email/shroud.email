import test from "node:test";
import assert from "node:assert/strict";
import { setupPasskeys } from "./passkeys.mjs";

function element(properties = {}) {
  const handlers = {};
  return {
    ...properties,
    handlers,
    addEventListener(name, handler) { handlers[name] = handler; },
  };
}

function environment({ login = true, supported = true, credentials } = {}) {
  const elements = {};
  if (login) {
    elements["login-form"] = element();
    elements["passkey-login-button"] = element({ hidden: true });
    elements["passkey-login-status"] = element({ textContent: "" });
  } else {
    elements["add-passkey-form"] = element({ action: "/settings/passkeys/options" });
    elements["add-passkey-password"] = element({ value: "a valid password" });
    elements["passkey-status"] = element({ textContent: "" });
  }

  const document = {
    getElementById: id => elements[id] ?? null,
    querySelector: () => ({ getAttribute: () => "csrf" }),
  };
  const window = {
    PublicKeyCredential: supported ? { isConditionalMediationAvailable: async () => true } : undefined,
    navigator: { credentials },
    location: { assign() {} },
  };

  return { document, window, elements };
}

test("conditional passkey autofill starts without opening a modal", async () => {
  const calls = [];
  const env = environment({ credentials: { get: options => { calls.push(options); return new Promise(() => {}); } } });
  const fetch = async () => ({ ok: true, json: async () => ({ publicKey: { challenge: "AQID", rpId: "localhost", userVerification: "required" } }) });

  await setupPasskeys({ ...env, fetch });

  assert.equal(calls.length, 1);
  assert.equal(calls[0].mediation, "conditional");
  assert.deepEqual([...calls[0].publicKey.challenge], [1, 2, 3]);
  assert.equal(env.elements["passkey-login-button"].hidden, false);
});

test("unsupported browser does not call server or interfere with password form", async () => {
  const env = environment({ supported: false });
  await setupPasskeys({ ...env, fetch: () => { throw Error("must not fetch"); } });
  assert.equal(env.elements["passkey-login-button"].hidden, true);
  assert.equal(env.elements["login-form"].handlers.submit, undefined);
});

test("manual picker aborts pending autofill and cancellation keeps password available", async () => {
  const calls = [];
  const env = environment({ credentials: { get: options => {
    calls.push(options);
    if (options.mediation === "conditional") return new Promise((_, reject) => options.signal.addEventListener("abort", () => reject(new DOMException("aborted", "AbortError"))));
    return Promise.reject(new DOMException("canceled", "NotAllowedError"));
  } } });
  const fetch = async () => ({ ok: true, json: async () => ({ publicKey: { challenge: "AQID", rpId: "localhost" } }) });

  await setupPasskeys({ ...env, fetch });
  await env.elements["passkey-login-button"].handlers.click();

  assert.equal(calls[0].signal.aborted, true);
  assert.equal(calls[1].mediation, undefined);
  assert.equal(env.elements["login-form"].handlers.submit, undefined);
});

test("enrollment sends binary attestation after requesting discoverable user-verified options", async () => {
  const requests = [];
  let receivedOptions;
  const env = environment({ login: false, credentials: { create: async options => {
    receivedOptions = options.publicKey;
    return { rawId: Uint8Array.from([9]).buffer, response: { attestationObject: Uint8Array.from([7]).buffer, clientDataJSON: Uint8Array.from([8]).buffer } };
  } } });
  const fetch = async (url, options) => {
    requests.push({ url, options });
    return url.endsWith("/options")
      ? { ok: true, json: async () => ({ publicKey: { challenge: "AQID", user: { id: "BAUG", name: "user@example.com", displayName: "user@example.com" }, excludeCredentials: [], authenticatorSelection: { residentKey: "required", userVerification: "required" } } }) }
      : { ok: true };
  };

  await setupPasskeys({ ...env, fetch });
  await env.elements["add-passkey-form"].handlers.submit({ preventDefault() {} });

  assert.equal(receivedOptions.authenticatorSelection.residentKey, "required");
  assert.equal(receivedOptions.authenticatorSelection.userVerification, "required");
  assert.deepEqual([...receivedOptions.user.id], [4, 5, 6]);
  assert.equal(JSON.parse(requests[1].options.body).attestationObject, "Bw");
  assert.equal(requests[0].options.headers["x-csrf-token"], "csrf");
});
