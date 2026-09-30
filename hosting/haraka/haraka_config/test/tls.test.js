'use strict';

const assert = require('node:assert/strict');
const { execFileSync } = require('node:child_process');
const { X509Certificate } = require('node:crypto');
const { once } = require('node:events');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const tls = require('node:tls');
const { after, test } = require('node:test');

const instance = fs.mkdtempSync(path.join(os.tmpdir(), 'shroud-haraka-tls-'));
const config = path.join(instance, 'config');
fs.mkdirSync(path.join(config, 'certs'), { recursive: true });
fs.copyFileSync(path.join(__dirname, '../config/tls.ini'), path.join(config, 'tls.ini'));
process.env.HARAKA = instance;
// Exercise the uncached reads used by the coordinated cron/Compose fix.
process.env.WITHOUT_CONFIG_CACHE = '1';
execFileSync('openssl', ['genpkey', '-genparam', '-algorithm', 'DH', '-pkeyopt', 'group:ffdhe2048', '-out', path.join(config, 'dhparams.pem')]);

function certificate(name) {
  const key = path.join(instance, `${name}.key`);
  const cert = path.join(instance, `${name}.crt`);
  execFileSync('openssl', ['req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '2',
    '-subj', '/CN=mail.example', '-addext', 'subjectAltName=DNS:mail.example', '-keyout', key, '-out', cert], { stdio: 'ignore' });
  return { key: fs.readFileSync(key), cert: fs.readFileSync(cert) };
}

const first = certificate('first');
const second = certificate('second');
function publish(pair) {
  fs.writeFileSync(path.join(config, 'certs/tls_key.pem'), pair.key);
  fs.writeFileSync(path.join(config, 'certs/tls_cert.pem'), pair.cert);
}
publish(first);
const harakaTls = require('Haraka/tls_socket');
after(() => {
  harakaTls.config.stop_watching('tls.ini');
  harakaTls.config.stop_watching('certs/tls_key.pem');
  fs.rmSync(instance, { recursive: true, force: true });
});

test('missing startup key is unavailable; malformed and mismatched pairs are rejected', async () => {
  try {
    fs.rmSync(path.join(config, 'certs/tls_key.pem'));
    const opts = await harakaTls.getSocketOpts('*');
    assert.ok(!opts.key[0]);

    publish({ key: first.key, cert: Buffer.from('not a certificate') });
    assert.throws(() => harakaTls.load_tls_ini(), /PEM|no start line/);
    publish({ key: first.key, cert: second.cert });
    assert.throws(() => harakaTls.load_tls_ini(), /key values mismatch/);
  } finally {
    publish(first);
    harakaTls.load_tls_ini();
  }
});

test('TLS default certificate and SNI fallback rotate after the cron tls.ini touch', { timeout: 15000 }, async t => {
  await harakaTls.getSocketOpts('*');
  const server = harakaTls.createServer(socket => {
    socket.on('error', () => {});
    socket.upgrade();
  });
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  t.after(() => new Promise(resolve => server.close(resolve)));

  async function fingerprint(servername) {
    const client = tls.connect({ host: '127.0.0.1', port: server.address().port, servername,
      rejectUnauthorized: false });
    await once(client, 'secureConnect');
    const cert = client.getPeerCertificate();
    assert.equal(tls.checkServerIdentity('mail.example', cert), undefined);
    assert.ok(tls.checkServerIdentity('wrong.example', cert));
    const result = cert.fingerprint256;
    client.destroy();
    await once(client, 'close');
    return result;
  }
  const oldFingerprint = new X509Certificate(first.cert).fingerprint256;
  for (const sni of [undefined, 'mail.example', 'unknown.example']) {
    assert.equal(await fingerprint(sni), oldFingerprint);
  }

  const reload = harakaTls.load_tls_ini;
  const reloaded = new Promise(resolve => {
    t.mock.method(harakaTls, 'load_tls_ini', (...args) => {
      const result = reload(...args);
      resolve();
      return result;
    });
  });
  publish(second);
  // Use a distinct mtime even on filesystems with coarse timestamp resolution.
  const nextMtime = new Date(Date.now() + 1000);
  fs.utimesSync(path.join(config, 'tls.ini'), nextMtime, nextMtime);
  await reloaded;
  const newFingerprint = new X509Certificate(second.cert).fingerprint256;
  assert.notEqual(newFingerprint, oldFingerprint);
  for (const sni of [undefined, 'mail.example', 'unknown.example']) {
    assert.equal(await fingerprint(sni), newFingerprint);
  }
});
