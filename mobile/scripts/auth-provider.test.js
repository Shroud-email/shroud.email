const assert = require('node:assert/strict');
const { test } = require('node:test');
const fs = require('node:fs');
const ts = require('typescript');

// Exercise the provider's event handlers with native APIs and React hooks controlled.
function provider(platform = 'android') {
  const storage = new Map();
  const state = [];
  const refs = [];
  const listeners = {};
  let cursor = 0;
  let mounted = false;
  let auth;
  let completeBrowser;
  let opened;
  const browserOpened = new Promise((resolve) => {
    opened = resolve;
  });
  const browserResult = new Promise((resolve) => {
    completeBrowser = resolve;
  });
  let exchanges = 0;
  let identityResponse;
  const account = { id: 'account-id', email: 'person@example.com' };
  const react = {
    createContext: () => ({ Provider: 'provider' }),
    createElement: (_type, props) => {
      auth = props.value;
    },
    useState(initial) {
      const index = cursor++;
      if (!(index in state)) state[index] = initial;
      return [
        state[index],
        (value) => {
          state[index] = value;
        },
      ];
    },
    useRef(initial) {
      const index = cursor++;
      return (refs[index] ??= { current: initial });
    },
    useEffect(effect) {
      if (!mounted) effect();
    },
  };
  react.default = react;
  const load = (file, imports = {}, fetch = global.fetch) => {
    const exports = {};
    new Function(
      'exports',
      'require',
      'process',
      'fetch',
      'setInterval',
      ts.transpileModule(fs.readFileSync(require.resolve(file), 'utf8'), {
        compilerOptions: {
          module: ts.ModuleKind.CommonJS,
          target: ts.ScriptTarget.ES2022,
          jsx: ts.JsxEmit.React,
        },
      }).outputText
    )(
      exports,
      (name) => {
        assert.ok(name in imports, `Unexpected import: ${name}`);
        return imports[name];
      },
      {
        env: {
          EXPO_PUBLIC_OAUTH_CLIENT_ID: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
        },
      },
      fetch,
      (handler) => {
        listeners.tick = handler;
        return 0;
      }
    );
    return exports;
  };
  const core = load('../src/auth/core.ts', {}, async (url) => {
    if (url.endsWith('/oauth/token')) {
      exchanges++;
      return Response.json({
        access_token: 'access',
        refresh_token: 'refresh',
        token_type: 'Bearer',
        expires_in: 3600,
        resource: 'https://app.shroud.email/api/v1',
      });
    }
    assert.ok(url.endsWith('/me'));
    if (identityResponse) {
      const response = identityResponse;
      identityResponse = null;
      return response;
    }
    return Response.json(account);
  });
  const context = load('../src/auth/context.tsx', {
    './core': core,
    react,
    'react-native': {
      Platform: { OS: platform, Version: '17.4' },
      AppState: {
        addEventListener: (_event, handler) => {
          listeners.active = handler;
          return { remove() {} };
        },
      },
    },
    'expo-linking': {
      getInitialURL: async () => null,
      addEventListener: (_event, handler) => {
        listeners.link = handler;
        return { remove() {} };
      },
    },
    'expo-secure-store': {
      getItemAsync: async (key) => storage.get(key) ?? null,
      setItemAsync: async (key, value) => {
        storage.set(key, value);
      },
      deleteItemAsync: async (key) => {
        storage.delete(key);
      },
    },
    'expo-web-browser': {
      openAuthSessionAsync: () => {
        opened();
        return browserResult;
      },
    },
    'expo-auth-session': {
      AuthRequest: class {
        state = 'state';
        codeVerifier = 'v'.repeat(43);
        async makeAuthUrlAsync() {
          return 'https://app.shroud.email/oauth/authorize';
        }
      },
      CodeChallengeMethod: { S256: 'S256' },
      ResponseType: { Code: 'code' },
    },
  });
  const render = () => {
    cursor = 0;
    context.AuthProvider({ children: null });
    mounted = true;
    return auth;
  };
  render();
  const callback =
    'https://app.shroud.email/oauth/callback?state=state&iss=https%3A%2F%2Fapp.shroud.email&code=code';
  return {
    render,
    storage,
    account,
    browserOpened,
    completeBrowser,
    active: () => listeners.active('active'),
    tick: () => listeners.tick(),
    callback: () => listeners.link({ url: callback }),
    success: () => completeBrowser({ type: 'success', url: callback }),
    identityResponse: (response) => {
      identityResponse = response;
    },
    exchanges: () => exchanges,
  };
}

// Drain the provider's asynchronous handlers without wall-clock sleeps.
const settle = () => new Promise((resolve) => setImmediate(resolve));

test('Android active then dismiss then callback completes sign-in', async () => {
  const app = provider();
  await settle();
  const signingIn = app.render().signIn();
  await app.browserOpened;
  app.active();
  app.completeBrowser({ type: 'dismiss' });
  await signingIn;
  assert.ok(app.storage.has('pending'));
  assert.equal(app.render().message, null);
  app.callback();
  await settle();
  assert.equal(app.exchanges(), 1);
  assert.deepEqual(app.render().account, app.account);
});

for (const result of ['dismiss', 'success']) {
  test(`Android callback before browser ${result} exchanges once without cancellation`, async () => {
    const app = provider();
    await settle();
    const signingIn = app.render().signIn();
    await app.browserOpened;
    app.callback();
    await settle();
    if (result === 'success') app.success();
    else app.completeBrowser({ type: result });
    await signingIn;
    assert.equal(app.exchanges(), 1);
    assert.equal(app.storage.has('pending'), false);
    assert.deepEqual(app.render().account, app.account);
    assert.equal(app.render().message, null);
  });
}

for (const [platform, result] of [
  ['android', 'cancel'],
  ['ios', 'dismiss'],
]) {
  test(`${platform} explicit ${result} blocks a late callback`, async () => {
    const app = provider(platform);
    await settle();
    const signingIn = app.render().signIn();
    await app.browserOpened;
    app.completeBrowser({ type: result });
    await signingIn;
    app.callback();
    await settle();
    assert.equal(app.exchanges(), 0);
    assert.equal(app.storage.has('pending'), false);
    assert.equal(app.render().account, null);
    assert.match(app.render().message, /cancelled/);
  });
}

test('periodic verification preserves identity while pending, clears it on failure, and clears recovered errors', async () => {
  const app = provider();
  await settle();
  const signingIn = app.render().signIn();
  await app.browserOpened;
  app.success();
  await signingIn;
  let completeVerification;
  app.identityResponse(
    new Promise((resolve) => {
      completeVerification = resolve;
    })
  );
  app.tick();
  await settle();
  assert.deepEqual(app.render().account, app.account);
  completeVerification(Response.json(app.account));
  await settle();
  assert.deepEqual(app.render().account, app.account);

  app.identityResponse(new Response('{}', { status: 500 }));
  app.tick();
  await settle();
  assert.equal(app.render().account, null);
  assert.match(app.render().message, /Unable to verify/);
  app.tick();
  await settle();
  assert.deepEqual(app.render().account, app.account);
  assert.equal(app.render().message, null);
});

test('unsupported native builds retain an enabled session cleanup button; web does not', () => {
  for (const platform of ['android', 'ios', 'web']) {
    let cleared = 0;
    const element = (type, props) => ({ type, props });
    const imports = {
      'react/jsx-runtime': { jsx: element, jsxs: element },
      'expo-device': { isDevice: true },
      'react-native': {
        Button: 'Button',
        Platform: { OS: platform },
        StyleSheet: { create: (styles) => styles },
      },
      'react-native-safe-area-context': { SafeAreaView: 'SafeAreaView' },
      '@/constants/theme': {
        Spacing: {},
        BottomTabInset: 0,
        MaxContentWidth: 400,
      },
      '@/auth/context': {
        unsupported: 'Sign-in is unavailable.',
        useAuth: () => ({
          account: null,
          busy: false,
          signOut: () => {
            cleared++;
          },
        }),
      },
    };
    for (const [file, name] of [
      ['animated-icon', 'AnimatedIcon'],
      ['hint-row', 'HintRow'],
      ['themed-text', 'ThemedText'],
      ['themed-view', 'ThemedView'],
      ['web-badge', 'WebBadge'],
    ])
      imports[`@/components/${file}`] = { [name]: name };
    const exports = {};
    new Function(
      'exports',
      'require',
      ts.transpileModule(
        fs.readFileSync(require.resolve('../src/app/index.tsx'), 'utf8'),
        {
          compilerOptions: {
            module: ts.ModuleKind.CommonJS,
            jsx: ts.JsxEmit.ReactJSX,
          },
        }
      ).outputText
    )(exports, (name) => imports[name]);
    const buttons = [];
    const walk = (node) => {
      if (!node) return;
      if (Array.isArray(node)) return node.forEach(walk);
      if (node.type === 'Button') buttons.push(node.props);
      walk(node.props?.children);
    };
    walk(exports.default());
    assert.equal(
      buttons.find((button) => button.title === 'Sign in').disabled,
      true
    );
    const cleanup = buttons.find(
      (button) => button.title === 'Clear session / sign out'
    );
    if (platform === 'web') assert.equal(cleanup, undefined);
    else {
      assert.equal(cleanup.disabled, false);
      cleanup.onPress();
      assert.equal(cleared, 1);
    }
  }
});
