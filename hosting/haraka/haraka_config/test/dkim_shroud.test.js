'use strict';

const assert = require('node:assert/strict');
const { createHash, generateKeyPairSync, verify } = require('node:crypto');
const { once } = require('node:events');
const fs = require('node:fs');
const net = require('node:net');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');
const { Pool } = require('pg');
const { Plugin } = require('Haraka/plugins');
const { createTransaction } = require('Haraka/transaction');

const keys = generateKeyPairSync('rsa', { modulusLength: 2048 });
const privateKey = keys.privateKey.export({ type: 'pkcs1', format: 'pem' });
const body = 'A forwarded message.\r\nSecond line.\r\n';

function setup(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'shroud-dkim-'));
  const keydir = path.join(root, 'config/dkim/base.example');
  fs.mkdirSync(keydir, { recursive: true });
  fs.writeFileSync(path.join(keydir, 'private'), privateKey);
  fs.writeFileSync(path.join(keydir, 'selector'), 'shroudemail\n');
  fs.copyFileSync(path.join(__dirname, '../config/dkim.ini'), path.join(root, 'config/dkim.ini'));
  fs.symlinkSync(path.join(__dirname, '../plugins'), path.join(root, 'plugins'));
  const previous = { HARAKA: process.env.HARAKA, EMAIL_DOMAIN: process.env.EMAIL_DOMAIN };
  process.env.HARAKA = root;
  process.env.EMAIL_DOMAIN = 'BASE.EXAMPLE';
  t.after(() => {
    for (const [key, value] of Object.entries(previous)) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
    require('haraka-config/lib/watch').closeAll();
    fs.rmSync(root, { recursive: true, force: true });
  });

  // Load and register the folder plugin through the real Haraka loader.
  const plugin = new Plugin('dkim_shroud');
  plugin._compile();
  plugin.register();
  assert.deepEqual(Object.keys(plugin.hooks), ['queue_outbound']);
  assert.equal(plugin.cfg.sign.headers, 'From');
  const shippedPlugins = fs.readFileSync(path.join(__dirname, '../config/plugins'), 'utf8').split('\n');
  assert.ok(shippedPlugins.includes('dkim_shroud'));
  assert.ok(!shippedPlugins.includes('dkim'));
  return { plugin, keydir };
}

async function message(from, envelope = 'base.example') {
  const transaction = createTransaction();
  transaction.mail_from = { host: envelope };
  const results = [];
  transaction.results = { add: (_plugin, result) => results.push(result) };
  for (const line of `From: ${from}\r\nTo: recipient@elsewhere.example\r\nSubject: DKIM test\r\n\r\n${body}`.split(/(?<=\n)/)) {
    transaction.add_data(Buffer.from(line));
  }
  await new Promise((resolve) => transaction.end_data(resolve));
  const logs = [];
  const log = (_plugin, text) => logs.push(text);
  return {
    transaction, results, logs,
    logdebug: log, loginfo: log, lognotice: log, logerror: log, logprotocol: log,
  };
}

function sign(plugin, connection) {
  return new Promise((resolve) => plugin.hook_pre_send_trans_email((...args) => resolve(args), connection));
}

function checkSignature(connection, from, domain) {
  const signature = connection.transaction.header.get('DKIM-Signature');
  assert.match(signature, new RegExp(`d=${domain.replaceAll('.', '\\.')}; s=shroudemail;`));
  assert.match(signature, /c=relaxed\/simple;/);
  assert.match(signature, /h=from;/);
  const expectedBodyHash = createHash('sha256').update(body).digest('base64');
  assert.ok(signature.includes(`bh=${expectedBodyHash};`));
  // Independently reconstruct RFC 6376 relaxed headers and verify with the public key.
  const unfolded = signature.trim().replace(/\r?\n[ \t]+/g, ' ');
  const encoded = unfolded.match(/\bb=([\s\S]*)$/)[1].replace(/\s/g, '');
  const unsigned = unfolded.replace(/\bb=[\s\S]*$/, 'b=');
  assert.ok(verify('RSA-SHA256', Buffer.from(`from:${from}\r\ndkim-signature:${unsigned}`),
    keys.publicKey, Buffer.from(encoded, 'base64')));
  assert.equal(connection.transaction.notes.dkim_signed, true);
}

test('base-domain signing retains upstream behavior and needs no database', async (t) => {
  const { plugin } = setup(t);
  t.mock.method(Pool.prototype, 'query', async () => { throw new Error('must not query'); });
  const connection = await message('sender@base.example');
  assert.deepEqual(await sign(plugin, connection), []);
  checkSignature(connection, 'sender@base.example', 'base.example');
});

test('concurrent custom domains use the shared key but retain distinct From domains', async (t) => {
  const { plugin } = setup(t);
  const queried = [];
  t.mock.method(Pool.prototype, 'query', async function (sql, params) {
    assert.equal(this.options.connectionTimeoutMillis, 5000);
    assert.equal(this.options.query_timeout, 5000);
    assert.match(sql, /lower\(domain\) = \$1/);
    assert.match(sql, /ownership_verified_at > .* - INTERVAL '24 hours'/);
    queried.push(params[0]);
    return { rows: [{ domain: params[0] }] };
  });
  const froms = ['external_at_sender.example_alias@First.example', 'alias@second.example'];
  const connections = await Promise.all(froms.map((from) => message(from)));
  assert.deepEqual(await Promise.all(connections.map((connection) => sign(plugin, connection))), [[], []]);
  checkSignature(connections[0], froms[0], 'first.example');
  checkSignature(connections[1], froms[1], 'second.example');
  assert.deepEqual(queried.sort(), ['first.example', 'second.example']);
});

test('unknown or expired domains continue unsigned without default-key fallback', async (t) => {
  const { plugin } = setup(t);
  plugin.cfg.sign.domain = 'base.example';
  plugin.cfg.sign.selector = 'shroudemail';
  plugin.private_key = privateKey;
  t.mock.method(Pool.prototype, 'query', async () => ({ rows: [] }));
  const connection = await message('sender@unverified.example');
  assert.deepEqual(await sign(plugin, connection), []);
  assert.equal(connection.transaction.header.get('DKIM-Signature'), '');
  assert.ok(connection.logs.some((log) => log.includes('unverified custom domain')));
});

test('database failure is logged and continues unsigned', async (t) => {
  const { plugin } = setup(t);
  t.mock.method(Pool.prototype, 'query', async () => { throw new Error('database unavailable'); });
  const connection = await message('alias@customer.example');
  assert.deepEqual(await sign(plugin, connection), []);
  assert.equal(connection.transaction.header.get('DKIM-Signature'), '');
  assert.ok(connection.logs.includes('database unavailable'));
});

test('a stalled PostgreSQL connection times out and continues unsigned', { timeout: 15000 }, async (t) => {
  const { plugin } = setup(t);
  const sockets = new Set();
  // Accept the real pg client's TCP connection but never answer its startup packet.
  const server = net.createServer((socket) => { sockets.add(socket); });
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  const previous = { PGHOST: process.env.PGHOST, PGPORT: process.env.PGPORT };
  process.env.PGHOST = '127.0.0.1';
  process.env.PGPORT = String(server.address().port);
  t.after(async () => {
    for (const [key, value] of Object.entries(previous)) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
    for (const socket of sockets) socket.destroy();
    await new Promise((resolve) => server.close(resolve));
  });
  const connection = await message('alias@customer.example');
  assert.deepEqual(await sign(plugin, connection), []);
  assert.equal(connection.transaction.header.get('DKIM-Signature'), '');
  assert.ok(connection.logs.some((log) => /timeout|timed out/i.test(log)));
});

test('missing installation key or selector continues unsigned', async (t) => {
  const { plugin } = setup(t);
  t.mock.method(Pool.prototype, 'query', async () => ({ rows: [{ domain: 'customer.example' }] }));
  for (const missing of ['private', 'selector']) {
    t.mock.method(plugin, 'load_key', (file) => {
      if (file.endsWith(`/${missing}`)) return '';
      return file.endsWith('/private') ? privateKey : 'shroudemail';
    });
    const connection = await message('alias@customer.example');
    assert.deepEqual(await sign(plugin, connection), []);
    assert.equal(connection.transaction.header.get('DKIM-Signature'), '');
    assert.ok(connection.logs.some((log) => log.startsWith('skipped: no ')));
  }
});

test('upstream signing-error callback and already-signed behavior are unchanged', async (t) => {
  const { plugin } = setup(t);
  t.mock.method(Pool.prototype, 'query', async () => ({ rows: [{ domain: 'customer.example' }] }));
  const error = new Error('signing stream failed');
  t.mock.method(plugin, 'run_sign_stream', async () => { throw error; });
  const connection = await message('alias@customer.example');
  assert.deepEqual(await sign(plugin, connection), [error]);
  assert.ok(connection.results.some((result) => result.err === error.message));
  connection.transaction.notes.dkim_signed = true;
  assert.deepEqual(await sign(plugin, connection), []);
  assert.equal(plugin.run_sign_stream.mock.callCount(), 1);
});
