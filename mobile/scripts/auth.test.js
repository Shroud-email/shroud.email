const assert = require('node:assert/strict');
const { test } = require('node:test');
const fs = require('node:fs');
const ts = require('typescript');
const moduleUnderTest = { exports: {} };
new Function(
  'exports',
  ts.transpileModule(
    fs.readFileSync(require.resolve('../src/auth/core.ts'), 'utf8'),
    {
      compilerOptions: {
        module: ts.ModuleKind.CommonJS,
        target: ts.ScriptTarget.ES2022,
      },
    }
  ).outputText
)(moduleUnderTest.exports);
const { AuthService, callbackCode, issuer, resource, redirectUri } =
  moduleUnderTest.exports;
const pending = {
  state: 'random-state',
  verifier: 'v'.repeat(43),
  created: 1000,
  clientId: 'registered-client',
};
const callback = `${redirectUri}?${new URLSearchParams({ state: pending.state, iss: issuer, code: 'code' })}`;
function store() {
  const data = new Map();
  return {
    data,
    async get(key) {
      return data.get(key) ?? null;
    },
    async set(key, value) {
      data.set(key, value);
    },
    async remove(key) {
      data.delete(key);
    },
  };
}
const response = (body) => new Response(JSON.stringify(body), { status: 200 });
const tokens = {
  access_token: 'access',
  refresh_token: 'rotated',
  token_type: 'Bearer',
  expires_in: 3600,
  resource,
};

test('strict callback state, issuer, URL, duplicates, transaction lifetime and verifier', () => {
  assert.equal(callbackCode(callback, pending, 1000, pending.clientId), 'code');
  for (const url of [
    callback.replace('random-state', 'wrong'),
    callback.replace(
      encodeURIComponent(issuer),
      encodeURIComponent(`${issuer}/`)
    ),
    callback.replace('https:', 'http:'),
    callback.replace('/oauth/callback', '/oauth/callback/'),
    `${callback}&code=other`,
    `${callback}&state=other`,
    `${callback}&iss=other`,
    `${callback}#fragment`,
    `${callback}&access_token=secret`,
  ]) {
    assert.throws(() => callbackCode(url, pending, 1000, pending.clientId));
  }
  for (const change of [
    { verifier: '' },
    { verifier: 'short' },
    { created: -600_000 },
    { created: 1001 },
    { clientId: 'other' },
  ]) {
    assert.throws(() =>
      callbackCode(callback, { ...pending, ...change }, 1000, pending.clientId)
    );
  }
});

test('cold-start persisted PKCE and simultaneous router/browser callback exchange once', async () => {
  const storage = store();
  await storage.set('pending', JSON.stringify(pending));
  let calls = 0;
  const service = new AuthService(
    storage,
    pending.clientId,
    async (url, options) => {
      calls++;
      assert.equal(url, `${issuer}/oauth/token`);
      const form = new URLSearchParams(options.body);
      assert.equal(form.get('code_verifier'), pending.verifier);
      assert.equal(form.get('redirect_uri'), redirectUri);
      assert.equal(form.get('resource'), resource);
      assert.equal(form.get('client_id'), pending.clientId);
      assert.equal(form.get('grant_type'), 'authorization_code');
      return response(tokens);
    },
    () => 1000
  );
  assert.deepEqual(
    await Promise.all([service.callback(callback), service.callback(callback)]),
    [true, false]
  );
  assert.equal(calls, 1);
  assert.equal(storage.data.has('pending'), false);
});

test('invalid callback never exchanges; ambiguous code failure is not replayed', async () => {
  const storage = store();
  let calls = 0;
  const service = new AuthService(
    storage,
    pending.clientId,
    async () => {
      calls++;
      throw new Error('offline');
    },
    () => 1000
  );
  await service.savePending(pending);
  await assert.rejects(
    service.callback(callback.replace('random-state', 'wrong'))
  );
  assert.equal(calls, 0);
  await assert.rejects(service.callback(callback));
  assert.equal(await service.callback(callback), false);
  assert.equal(calls, 1);
});

test('cancelled transactions cannot be completed by a late callback', async () => {
  const storage = store();
  const service = new AuthService(
    storage,
    pending.clientId,
    async () => {
      throw new Error('unexpected exchange');
    },
    () => 1000
  );
  await service.savePending(pending);
  await service.cancelPending();
  assert.equal(await service.callback(callback), false);
  assert.equal(storage.data.size, 0);
});

test('token responses for the wrong resource are not persisted', async () => {
  const storage = store();
  const service = new AuthService(
    storage,
    pending.clientId,
    async () => response({ ...tokens, resource: `${issuer}/mcp` }),
    () => 1000
  );
  await service.savePending(pending);
  await assert.rejects(service.callback(callback), /Invalid token response/);
  assert.equal(storage.data.size, 0);
});

test('revoked account credentials cannot supply cached identity', async () => {
  const storage = store();
  await storage.set(
    'tokens',
    JSON.stringify({ access: 'revoked', refresh: 'refresh', expires: 999999 })
  );
  const service = new AuthService(
    storage,
    pending.clientId,
    async () => new Response('{}', { status: 401 }),
    () => 1000
  );
  await assert.rejects(service.account(), /Unable to verify/);
  assert.equal(await storage.get('tokens'), null);
  assert.equal(await service.account(), null);
});

test('concurrent refreshes serialize and persist rotated token before any subsequent refresh', async () => {
  const storage = store();
  await storage.set(
    'tokens',
    JSON.stringify({ access: 'old', refresh: 'original', expires: 0 })
  );
  let now = 1000;
  const used = [];
  const service = new AuthService(
    storage,
    pending.clientId,
    async (url, options) => {
      if (url.endsWith('/oauth/token')) {
        used.push(new URLSearchParams(options.body).get('refresh_token'));
        await new Promise((resolve) => setTimeout(resolve, 10));
        return response({ ...tokens, refresh_token: `rotated-${used.length}` });
      }
      assert.equal(
        JSON.parse(await storage.get('tokens')).refresh,
        `rotated-${used.length}`
      );
      return response({ id: 'server-id', email: 'server@example.com' });
    },
    () => now
  );
  const accounts = await Promise.all([
    service.account(),
    service.account(),
    service.account(),
  ]);
  assert.equal(accounts[0].id, 'server-id');
  assert.deepEqual(used, ['original']);
  now += 3600_000;
  await Promise.all([service.account(), service.account()]);
  assert.deepEqual(used, ['original', 'rotated-1']);
});

test('refresh failure discards replay-risk credentials and offline logout clears locally', async () => {
  const storage = store();
  const service = new AuthService(storage, pending.clientId, async () => {
    throw new Error('offline');
  });
  await storage.set(
    'tokens',
    JSON.stringify({ access: 'old', refresh: 'old', expires: 0 })
  );
  await assert.rejects(service.account());
  assert.equal(await storage.get('tokens'), null);
  await storage.set('tokens', JSON.stringify({ refresh: 'connection' }));
  await service.savePending(pending);
  await assert.rejects(service.logout(), /Signed out locally/);
  assert.equal(storage.data.size, 0);
});
