'use strict';

const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { after, test } = require('node:test');

const instance = fs.mkdtempSync(path.join(os.tmpdir(), 'shroud-haraka-'));
fs.cpSync(path.join(__dirname, '../config'), path.join(instance, 'config'), { recursive: true });
fs.symlinkSync(path.join(__dirname, '../plugins'), path.join(instance, 'plugins'));
// Signing is opt-in, but exercise the migrated signing hook and domain key layout.
fs.appendFileSync(path.join(instance, 'config/dkim.ini'), '\n[sign]\nenabled=true\n');
process.env.HARAKA = instance;
process.env.SMTP_USERNAME = 'relay-user';
process.env.SMTP_PASSWORD = 'test-only-password';
after(() => fs.rmSync(instance, { recursive: true, force: true }));

require('haraka-config/lib/reader').watch_files = false;
const plugins = require('Haraka/plugins');
const { OK, DENY } = require('haraka-constants');
const { Address } = require('@haraka/email-address');
const Results = require('haraka-results');

test('all configured plugins load and register on the pinned Haraka', t => {
  assert.equal(require('Haraka/package.json').version, '3.3.4');
  // Loading hooks is under test; do not contact public DNSBLs during registration.
  t.mock.method(require('haraka-plugin-dns-list'), 'check_zones', () => {});
  plugins.load_plugins();
  assert.deepEqual(plugins.plugin_list, [
    'dns-list', 'helo.checks', 'tls', 'auth/environment_variable',
    'mail_from.is_resolvable', 'spf', 'rcpt_to.in_host_list_shroud',
    'headers', 'spamassassin', 'dkim', 'bounce_logger', 'queue/smtp_forward',
  ]);
  assert.equal(plugins.registered_hooks.mail.filter(h => h.method === 'check_backscatterer').length, 1);
  assert.equal(plugins.registered_hooks.queue_outbound.filter(h => h.plugin === 'dkim').length, 1);
  assert.equal(plugins.registered_hooks.data_post.some(h => h.method === 'dkim_verify'), false);
  const dns = plugins.registered_plugins['dns-list'];
  assert.deepEqual([...dns.cfg.main.zones], ['zen.spamhaus.org']);
  assert.equal(dns.cfg.main.search, 'first');
  const mx = plugins.registered_plugins['mail_from.is_resolvable'];
  assert.equal(mx.dns_timeout_ms, 20000);
  assert.equal(mx.reject_no_mx, 'deny');
  assert.equal(mx.cfg.main.allow_mx_ip, true);
  const forward = plugins.registered_plugins['queue/smtp_forward'];
  assert.equal(forward.cfg.main.host, 'web');
  assert.equal(forward.cfg.main.port, 1587);
  assert.equal(forward.cfg.main.enable_tls, false);
  assert.equal(forward.cfg.main.check_recipient, false);
  const cfg = plugins.config.get('connection.ini');
  assert.equal(cfg.headers.max_lines, 1000);
  assert.equal(cfg.headers.max_received, 100);
});

test('pooled host lookup preserves the existing unfiltered domain policy', t => {
  const rcpt = plugins.registered_plugins['rcpt_to.in_host_list_shroud'];
  const query = t.mock.method(require('pg').Pool.prototype, 'query', (sql, cb) => {
    assert.equal(sql, 'SELECT domain FROM custom_domains');
    cb(null, { rows: [{ domain: 'Custom.Example' }] });
  });
  let domains;
  rcpt.load_host_list(result => { domains = result; });
  assert.equal(query.mock.callCount(), 1);
  assert.ok(domains.has('custom.example'));
});

test('environment auth inherits working PLAIN, LOGIN and CRAM-MD5 checks', () => {
  const auth = plugins.registered_plugins['auth/environment_variable'];
  for (const [is_private, enabled, expected] of [[false, false, false], [true, false, true], [false, true, true]]) {
    const conn = { remote: { is_private }, tls: { enabled }, capabilities: [], notes: {}, logdebug() {} };
    let calls = 0;
    auth.hook_capabilities(() => calls++, conn);
    assert.equal(calls, 1);
    assert.equal(conn.capabilities.length > 0, expected);
    if (expected) assert.deepEqual([...conn.notes.allowed_auth_methods], ['CRAM-MD5', 'PLAIN', 'LOGIN']);
  }
  for (const [user, password, expected] of [
    ['relay-user', 'test-only-password', true], ['relay-user', 'wrong', false], ['unknown', 'test-only-password', false],
  ]) {
    auth.check_plain_passwd({}, user, password, result => assert.equal(result, expected));
  }
  const conn = { notes: { auth_ticket: '<test-challenge@mail.example>' } };
  const digest = crypto.createHmac('md5', 'test-only-password').update(conn.notes.auth_ticket).digest('hex');
  auth.check_cram_md5_passwd(conn, 'relay-user', digest, result => assert.equal(result, true));
  auth.check_cram_md5_passwd(conn, 'relay-user', 'wrong', result => assert.equal(result, false));
});

test('local recipient, anti-spoof and relay decisions retain their boundaries', t => {
  const rcpt = plugins.registered_plugins['rcpt_to.in_host_list_shroud'];
  t.mock.method(rcpt, 'load_host_list', cb => cb(new Set(['alias.example', 'custom.example'])));
  const connection = relaying => ({
    relaying, logdebug() {}, transaction: { results: new Results({ logdebug() {}, loginfo() {} }), notes: {} },
  });
  const hook = (method, conn, address) => {
    let called = false;
    let result;
    rcpt[method](code => { called = true; result = code; }, conn, [new Address(address)]);
    assert.equal(called, true);
    return result;
  };
  assert.equal(hook('hook_rcpt', connection(false), 'user@custom.example'), OK);
  assert.equal(hook('hook_rcpt', connection(false), 'user@external.example'), undefined);
  assert.equal(hook('hook_mail', connection(false), 'user@alias.example'), DENY);
  const relay = connection(true);
  assert.equal(hook('hook_mail', relay, 'user@alias.example'), undefined);
  assert.equal(relay.transaction.notes.local_sender, true);
  assert.equal(hook('hook_rcpt', relay, 'user@external.example'), OK);
  const external = connection(true);
  hook('hook_mail', external, 'user@external.example');
  assert.equal(hook('hook_rcpt', external, 'user@other.example'), undefined);
  assert.equal(hook('hook_mail', connection(false), '<>'), undefined);
});

test('bounce hook binds the Haraka plugin and continues once', t => {
  const bounce = plugins.registered_plugins.bounce_logger;
  const log = t.mock.method(bounce, 'logwarn', () => {});
  let calls = 0;
  bounce.hook_bounce(() => calls++, {}, '550 mailbox unavailable');
  assert.equal(calls, 1);
  assert.equal(log.mock.calls[0].arguments[0], 'Bounced message: 550 mailbox unavailable');
});

test('DKIM signs using existing per-domain private/selector files', async () => {
  const dkim = plugins.registered_plugins.dkim;
  const { privateKey } = crypto.generateKeyPairSync('rsa', { modulusLength: 2048 });
  const keydir = path.join(instance, 'config/dkim/alias.example');
  fs.mkdirSync(keydir, { recursive: true });
  fs.writeFileSync(path.join(keydir, 'private'), privateKey.export({ type: 'pkcs1', format: 'pem' }));
  fs.writeFileSync(path.join(keydir, 'selector'), 'shroudemail\n');
  const txn = require('Haraka/transaction').createTransaction();
  txn.mail_from = new Address('sender@alias.example');
  txn.results = new Results({ logdebug() {} });
  for (const line of ['From: sender@alias.example', 'To: recipient@external.example', 'Subject: Upgrade test', '', 'Test body']) {
    txn.add_data(Buffer.from(`${line}\r\n`));
  }
  await new Promise(resolve => txn.end_data(resolve));
  const conn = { transaction: txn, logdebug() {}, logerror(_plugin, message) { throw new Error(message); }, loginfo() {}, lognotice() {}, logprotocol() {} };
  await new Promise((resolve, reject) => dkim.hook_pre_send_trans_email(err => err ? reject(err) : resolve(), conn));
  const signature = txn.header.get('DKIM-Signature');
  assert.match(signature, /d=alias\.example/);
  assert.match(signature, /s=shroudemail/);
  // The expected body digest is computed independently of the signing plugin.
  assert.ok(signature.includes(`bh=${crypto.createHash('sha256').update('Test body\r\n').digest('base64')}`));
  assert.equal(txn.notes.dkim_signed, true);
});
