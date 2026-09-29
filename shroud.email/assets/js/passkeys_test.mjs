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
    elements["passkey-login"] = element({ hidden: true });
    elements["passkey-login-button"] = element({ hidden: true });
    elements["passkey-login-status"] = element({ textContent: "" });
  } else {
    elements["add-passkey-form"] = element({ action: "/settings/passkeys/options" });
    elements["add-passkey-password"] = element({ value: "a valid password" });
    elements["add-passkey-submit"] = element({ disabled: false });
    elements["passkey-status"] = element({ textContent: "", dataset: {} });
  }

  const document = {
    getElementById: id => elements[id] ?? null,
    querySelector: () => ({ getAttribute: () => "csrf" }),
  };
  const window = {
    PublicKeyCredential: supported ? { isConditionalMediationAvailable: async () => true } : undefined,
    navigator: { credentials },
    setTimeout,
    clearTimeout,
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
  assert.equal(env.elements["passkey-login"].hidden, false);
  assert.equal(env.elements["passkey-login-button"].hidden, false);
});

test("unsupported browser does not call server or interfere with password form", async () => {
  const env = environment({ supported: false });
  await setupPasskeys({ ...env, fetch: () => { throw Error("must not fetch"); } });
  assert.equal(env.elements["passkey-login"].hidden, true);
  assert.equal(env.elements["passkey-login-button"].hidden, true);
  assert.equal(env.elements["login-form"].handlers.submit, undefined);
});

test("unsupported browser keeps enrollment on settings with an explanation", async () => {
  const env = environment({ login: false, supported: false });
  await setupPasskeys({ ...env, fetch: () => { throw Error("must not fetch"); } });
  let prevented = false;
  await env.elements["add-passkey-form"].handlers.submit({ preventDefault() { prevented = true; } });
  assert.equal(prevented, true);
  assert.match(env.elements["passkey-status"].textContent, /does not support passkeys/);
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

test("manual picker wins while conditional capability detection is pending", async () => {
  let resolveCapability;
  const calls = [];
  const env = environment({ credentials: { get: options => {
    calls.push(options);
    return Promise.reject(new DOMException("canceled", "NotAllowedError"));
  } } });
  env.window.PublicKeyCredential.isConditionalMediationAvailable = () =>
    new Promise(resolve => { resolveCapability = resolve; });
  const fetch = async () => ({ ok: true, json: async () => ({ publicKey: { challenge: "AQID" } }) });

  const setup = setupPasskeys({ ...env, fetch });
  await env.elements["passkey-login-button"].handlers.click();
  resolveCapability(true);
  await setup;

  assert.equal(calls.length, 1);
  assert.equal(calls[0].mediation, undefined);
});

test("manual picker wins when conditional options finish late", async () => {
  let resolveConditionalOptions;
  let requests = 0;
  const calls = [];
  const env = environment({ credentials: { get: options => {
    calls.push(options);
    return Promise.reject(new DOMException("canceled", "NotAllowedError"));
  } } });
  const fetch = () => ++requests === 1
    ? new Promise(resolve => { resolveConditionalOptions = resolve; })
    : Promise.resolve({ ok: true, json: async () => ({ publicKey: { challenge: "AQID" } }) });

  const setup = setupPasskeys({ ...env, fetch });
  await Promise.resolve();
  await env.elements["passkey-login-button"].handlers.click();
  resolveConditionalOptions({ ok: true, json: async () => ({ publicKey: { challenge: "AQID" } }) });
  await setup;

  assert.equal(calls.length, 1);
  assert.equal(calls[0].mediation, undefined);
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
      ? { ok: true, json: async () => ({ token: "signed-token", publicKey: { challenge: "AQID", user: { id: "BAUG", name: "user@example.com", displayName: "user@example.com" }, excludeCredentials: [], authenticatorSelection: { residentKey: "required", userVerification: "required" } } }) }
      : { ok: true };
  };

  await setupPasskeys({ ...env, fetch });
  await env.elements["add-passkey-form"].handlers.submit({ preventDefault() {} });

  assert.equal(receivedOptions.authenticatorSelection.residentKey, "required");
  assert.equal(receivedOptions.authenticatorSelection.userVerification, "required");
  assert.deepEqual([...receivedOptions.user.id], [4, 5, 6]);
  assert.equal(JSON.parse(requests[1].options.body).attestationObject, "Bw");
  assert.equal(JSON.parse(requests[1].options.body).token, "signed-token");
  assert.equal(requests[0].options.headers["x-csrf-token"], "csrf");
});

test("enrollment remains disabled while saving and restores the button on failure", async () => {
  let rejectSave;
  let saving;
  const savingStarted = new Promise(resolve => { saving = resolve; });
  const env = environment({ login: false, credentials: { create: async () => ({
    rawId: Uint8Array.from([9]).buffer,
    response: { attestationObject: Uint8Array.from([7]).buffer, clientDataJSON: Uint8Array.from([8]).buffer },
  }) } });
  const fetch = async url => url.endsWith("/options")
    ? { ok: true, json: async () => ({ token: "signed-token", publicKey: {
      challenge: "AQID", user: { id: "BAUG" }, excludeCredentials: [],
    } }) }
    : new Promise((_, reject) => { rejectSave = reject; saving(); });

  await setupPasskeys({ ...env, fetch });
  const submission = env.elements["add-passkey-form"].handlers.submit({ preventDefault() {} });
  await savingStarted;
  assert.equal(env.elements["add-passkey-submit"].disabled, true);
  assert.match(env.elements["passkey-status"].textContent, /Saving your passkey/);
  rejectSave(new Error("network unavailable"));
  await submission;
  assert.equal(env.elements["add-passkey-submit"].disabled, false);
  assert.equal(env.elements["passkey-status"].dataset.state, "error");
});

test("saving an enrolled passkey times out and becomes retryable", async () => {
  let timeout;
  let saving;
  const savingStarted = new Promise(resolve => { saving = resolve; });
  const env = environment({ login: false, credentials: { create: async () => ({
    rawId: Uint8Array.from([9]).buffer,
    response: { attestationObject: Uint8Array.from([7]).buffer, clientDataJSON: Uint8Array.from([8]).buffer },
  }) } });
  env.window.setTimeout = callback => { timeout = callback; return 1; };
  env.window.clearTimeout = () => {};
  const fetch = async (url, options) => url.endsWith("/options")
    ? { ok: true, json: async () => ({ token: "signed-token", publicKey: {
      challenge: "AQID", user: { id: "BAUG" }, excludeCredentials: [],
    } }) }
    : new Promise((_, reject) => {
      saving();
      options.signal?.addEventListener("abort", () => reject(new DOMException("aborted", "AbortError")));
    });

  await setupPasskeys({ ...env, fetch });
  const submission = env.elements["add-passkey-form"].handlers.submit({ preventDefault() {} });
  await savingStarted;
  assert.match(env.elements["passkey-status"].textContent, /Saving your passkey/);
  timeout();
  await submission;
  assert.match(env.elements["passkey-status"].textContent, /timed out.*try again/i);
  assert.equal(env.elements["add-passkey-submit"].disabled, false);
});

test("stalled enrollment reports a timeout and allows another attempt", async () => {
  let timeout;
  let credentialStarted;
  const started = new Promise(resolve => { credentialStarted = resolve; });
  let calls = 0;
  let attempts = 0;
  const env = environment({ login: false, credentials: { create: ({ signal }) => {
    if (++attempts === 2) return Promise.reject(new DOMException("canceled", "NotAllowedError"));
    credentialStarted();
    return new Promise((_, reject) => signal.addEventListener("abort", () =>
      reject(new DOMException("aborted", "AbortError"))));
  } } });
  env.window.setTimeout = (callback, delay) => { timeout = callback; assert.equal(delay, 60_000); return 1; };
  env.window.clearTimeout = () => {};
  const fetch = async () => {
    calls++;
    return { ok: true, json: async () => ({ token: "signed-token", publicKey: {
      challenge: "AQID", user: { id: "BAUG" }, excludeCredentials: [],
    } }) };
  };

  await setupPasskeys({ ...env, fetch });
  const submission = env.elements["add-passkey-form"].handlers.submit({ preventDefault() {} });
  await started;
  assert.match(env.elements["passkey-status"].textContent, /Waiting/);
  assert.equal(env.elements["add-passkey-submit"].disabled, true);
  timeout();
  await submission;

  assert.match(env.elements["passkey-status"].textContent, /timed out.*try again/i);
  assert.equal(env.elements["add-passkey-submit"].disabled, false);
  assert.equal(env.elements["passkey-status"].dataset.state, "error");
  assert.equal(calls, 1);
  await env.elements["add-passkey-form"].handlers.submit({ preventDefault() {} });
  assert.equal(calls, 2);
  assert.equal(attempts, 2);
});
