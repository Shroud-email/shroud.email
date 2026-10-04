import test from "node:test";
import assert from "node:assert/strict";
import { createPasskeyHooks } from "./passkeys.mjs";

const tick = () => new Promise((resolve) => setImmediate(resolve));
const bytes = (...values) => Uint8Array.from(values).buffer;

function setup({ credentials = {}, conditional = true, timers = false } = {}) {
  const handlers = {};
  const buttonHandlers = new Set();
  const events = [];
  const timeouts = [];
  const window = {
    PublicKeyCredential: {
      isConditionalMediationAvailable: async () => conditional,
    },
    navigator: { credentials },
    setTimeout: timers
      ? (callback) => (timeouts.push(callback), timeouts.length)
      : setTimeout,
    clearTimeout: timers ? () => {} : clearTimeout,
  };
  const el = {
    addEventListener: (_name, handler) => buttonHandlers.add(handler),
    removeEventListener: (_name, handler) => buttonHandlers.delete(handler),
  };
  const hooks = createPasskeyHooks(window);
  function mount(hook) {
    const instance = Object.assign({}, hook, {
      el,
      handleEvent: (name, handler) => {
        handlers[name] = handler;
      },
      pushEvent(name, payload, callback) {
        events.push({ name, payload, callback });
      },
    });
    instance.mounted();
    return instance;
  }
  const click = () =>
    [...buttonHandlers][0]({ target: { closest: () => ({}) } });
  return {
    hooks,
    handlers,
    events,
    timeouts,
    buttonHandlers,
    mount,
    window,
    click,
  };
}

function registrationPayload() {
  return {
    token: "registration-token",
    publicKey: {
      challenge: "AQID",
      user: { id: "BAUG" },
      excludeCredentials: [{ type: "public-key", id: "Bwg" }],
    },
  };
}

function assertionReply() {
  return {
    token: "login-token",
    publicKey: {
      challenge: "AQID",
      allowCredentials: [{ type: "public-key", id: "BAU" }],
    },
  };
}

test("capability detection requires the API method for each operation", async () => {
  for (const [credentials, canCreate, canGet] of [
    [undefined, false, false],
    [{}, false, false],
    [{ create() {} }, true, false],
    [{ get() {} }, false, true],
  ]) {
    const env = setup({ credentials, conditional: false });
    env.window.navigator.credentials = credentials;
    const registration = env.mount(env.hooks.PasskeyRegistration);
    assert.deepEqual(env.events.at(-1).payload, { supported: canCreate });
    registration.reconnected();
    assert.deepEqual(env.events.at(-1).payload, { supported: canCreate });

    const login = env.mount(env.hooks.PasskeyLogin);
    assert.deepEqual(env.events.at(-1).payload, { supported: canGet });
    login.reconnected();
    assert.deepEqual(env.events.at(-1).payload, { supported: canGet });
    await tick();
    assert.equal(
      env.events.some((event) => event.name === "passkey_options"),
      false,
    );
  }

  const env = setup({ credentials: { create() {}, get() {} } });
  env.window.PublicKeyCredential = undefined;
  env.mount(env.hooks.PasskeyRegistration);
  env.mount(env.hooks.PasskeyLogin);
  assert.equal(
    env.events.every((event) => event.payload.supported === false),
    true,
  );
});

test("registration decodes options and sends an encoded assertion without navigation", async () => {
  let options;
  const env = setup({
    credentials: {
      create: async (value) => {
        options = value;
        return {
          rawId: bytes(9),
          response: { attestationObject: bytes(7), clientDataJSON: bytes(8) },
        };
      },
    },
  });
  env.mount(env.hooks.PasskeyRegistration);
  const work = env.handlers["passkey-register"](registrationPayload());
  await tick();
  const saved = env.events.find((event) => event.name === "passkey_registered");
  saved.callback({});
  await work;

  assert.deepEqual([...options.publicKey.challenge], [1, 2, 3]);
  assert.deepEqual([...options.publicKey.user.id], [4, 5, 6]);
  assert.deepEqual([...options.publicKey.excludeCredentials[0].id], [7, 8]);
  assert.deepEqual(saved.payload, {
    token: "registration-token",
    rawId: "CQ",
    attestationObject: "Bw",
    clientDataJSON: "CA",
  });
  assert.deepEqual(
    env.events
      .filter((e) => e.name === "passkey_status")
      .map((e) => e.payload.phase),
    ["waiting", "saving"],
  );
});

test("registration reports unsupported, cancellation, and timeout reasons", async () => {
  const unsupported = setup({ credentials: {} });
  unsupported.window.PublicKeyCredential = undefined;
  unsupported.mount(unsupported.hooks.PasskeyRegistration);
  await unsupported.handlers["passkey-register"](registrationPayload());
  assert.equal(unsupported.events.at(-1).payload.reason, "unsupported");

  const canceled = setup({
    credentials: {
      create: async () => {
        throw new DOMException("no", "NotAllowedError");
      },
    },
  });
  canceled.mount(canceled.hooks.PasskeyRegistration);
  await canceled.handlers["passkey-register"](registrationPayload());
  assert.equal(canceled.events.at(-1).payload.reason, "canceled");

  const timeout = setup({
    timers: true,
    credentials: {
      create: ({ signal }) =>
        new Promise((_, reject) =>
          signal.addEventListener("abort", () =>
            reject(new DOMException("abort", "AbortError")),
          ),
        ),
    },
  });
  timeout.mount(timeout.hooks.PasskeyRegistration);
  const work = timeout.handlers["passkey-register"](registrationPayload());
  timeout.timeouts[0]();
  await work;
  assert.equal(timeout.events.at(-1).payload.reason, "timeout");
});

test("manual login invalidates late conditional options and sends assertion", async () => {
  const gets = [];
  const env = setup({
    credentials: {
      get: async (options) => {
        gets.push(options);
        return {
          rawId: bytes(1),
          response: {
            userHandle: bytes(2),
            authenticatorData: bytes(3),
            clientDataJSON: bytes(4),
            signature: bytes(5),
          },
        };
      },
    },
  });
  env.mount(env.hooks.PasskeyLogin);
  await tick();
  const conditionalOptions = env.events.find(
    (e) => e.name === "passkey_options",
  );
  env.click();
  const optionsEvents = env.events.filter((e) => e.name === "passkey_options");
  conditionalOptions.callback(assertionReply());
  optionsEvents[1].callback(assertionReply());
  await tick();

  assert.equal(gets.length, 1);
  assert.equal(gets[0].mediation, undefined);
  assert.deepEqual([...gets[0].publicKey.allowCredentials[0].id], [4, 5]);
  const assertion = env.events.find((e) => e.name === "passkey_assertion");
  assert.equal(assertion.payload.signature, "BQ");
  assertion.callback({});
});

test("registration times out even if the authenticator ignores abort and discards its late result", async () => {
  let finish;
  const env = setup({
    timers: true,
    credentials: {
      create: () =>
        new Promise((resolve) => {
          finish = resolve;
        }),
    },
  });
  env.mount(env.hooks.PasskeyRegistration);
  const work = env.handlers["passkey-register"](registrationPayload());
  env.timeouts[0]();
  assert.equal(env.events.at(-1).payload.reason, "timeout");
  finish({
    rawId: bytes(9),
    response: { attestationObject: bytes(7), clientDataJSON: bytes(8) },
  });
  await work;
  assert.equal(
    env.events.some((event) => event.name === "passkey_registered"),
    false,
  );
});

test("closing the dialog aborts enrollment and suppresses late authenticator results", async () => {
  let finish;
  let signal;
  const env = setup({
    credentials: {
      create: (options) => {
        signal = options.signal;
        return new Promise((resolve) => {
          finish = resolve;
        });
      },
    },
  });
  env.mount(env.hooks.PasskeyRegistration);
  const work = env.handlers["passkey-register"](registrationPayload());
  env.handlers["passkey-cancel"]();
  assert.equal(signal.aborted, true);
  finish({
    rawId: bytes(9),
    response: { attestationObject: bytes(7), clientDataJSON: bytes(8) },
  });
  await work;
  assert.equal(
    env.events.some((event) => event.name === "passkey_registered"),
    false,
  );
  assert.equal(
    env.events.some((event) => event.name === "passkey_error"),
    false,
  );
});

test("conditional cancellation is quiet while modal cancellation is reported", async () => {
  const env = setup({
    credentials: {
      get: async () => {
        throw new DOMException("no", "NotAllowedError");
      },
    },
  });
  env.mount(env.hooks.PasskeyLogin);
  await tick();
  env.events
    .find((e) => e.name === "passkey_options")
    .callback(assertionReply());
  await tick();
  assert.equal(
    env.events.some((e) => e.name === "passkey_login_error"),
    false,
  );

  env.click();
  env.events
    .filter((e) => e.name === "passkey_options")
    .at(-1)
    .callback(assertionReply());
  await tick();
  assert.equal(env.events.at(-1).payload.reason, "canceled");
});

test("modal timeout invalidates late options", async () => {
  const env = setup({
    timers: true,
    credentials: {
      get: () => {
        throw Error("must not run");
      },
    },
  });
  env.mount(env.hooks.PasskeyLogin);
  await tick();
  env.click();
  const manual = env.events.filter((e) => e.name === "passkey_options").at(-1);
  env.timeouts[0]();
  manual.callback(assertionReply());
  assert.equal(env.events.at(-1).payload.reason, "timeout");
});

test("reconnection restores capability and conditional login without duplicating click handlers", async () => {
  const env = setup({
    credentials: { create() {}, get: () => new Promise(() => {}) },
  });
  const registration = env.mount(env.hooks.PasskeyRegistration);
  registration.disconnected();
  registration.reconnected();
  assert.deepEqual(env.events.at(-1).payload, { supported: true });

  const login = env.mount(env.hooks.PasskeyLogin);
  await tick();
  const before = env.events.filter(
    (event) => event.name === "passkey_options",
  ).length;
  login.disconnected();
  login.reconnected();
  await tick();
  assert.equal(
    env.events.filter((event) => event.name === "passkey_options").length,
    before + 1,
  );
  assert.equal(env.buttonHandlers.size, 1);
});

test("destruction aborts and suppresses late registration and login responses", async () => {
  let registrationSignal;
  const registration = setup({
    credentials: {
      create: ({ signal }) => {
        registrationSignal = signal;
        return new Promise(() => {});
      },
    },
  });
  const registrationHook = registration.mount(
    registration.hooks.PasskeyRegistration,
  );
  registration.handlers["passkey-register"](registrationPayload());
  registrationHook.destroyed();
  assert.equal(registrationSignal.aborted, true);
  assert.equal(
    registration.events.some((e) => e.name === "passkey_error"),
    false,
  );

  const login = setup({
    credentials: {
      get: () => {
        throw Error("must not run");
      },
    },
  });
  const loginHook = login.mount(login.hooks.PasskeyLogin);
  await tick();
  const options = login.events.find((e) => e.name === "passkey_options");
  loginHook.destroyed();
  options.callback(assertionReply());
  assert.equal(login.buttonHandlers.size, 0);
  assert.equal(
    login.events.some((e) => e.name === "passkey_assertion"),
    false,
  );

  const remounted = login.mount(login.hooks.PasskeyLogin);
  assert.equal(login.buttonHandlers.size, 1);
  remounted.disconnected();
});

test("manual rate-limit replies preserve server retry guidance without invoking WebAuthn", () => {
  const env = setup({
    conditional: false,
    timers: true,
    credentials: {
      get: () => {
        throw Error("must not run");
      },
    },
  });
  const hook = env.mount(env.hooks.PasskeyLogin);
  hook.startPasskeyLogin(false);
  const request = env.events.find((e) => e.name === "passkey_options");
  request.callback({ error: "Too many requests", retry_after: 30 });
  assert.equal(
    env.events.some((e) => e.name === "passkey_login_error"),
    false,
  );
  assert.equal(hook.passkeyTimer, null);
  assert.equal(hook.passkeyController, null);
});
