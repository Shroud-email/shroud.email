'use strict';

const assert = require('node:assert/strict');
const { execFileSync, spawn } = require('node:child_process');
const { X509Certificate } = require('node:crypto');
const { once } = require('node:events');
const fs = require('node:fs');
const net = require('node:net');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');
const tls = require('node:tls');
const { setTimeout: delay } = require('node:timers/promises');

test('activates initial and repeated bundles on live Haraka TLS sockets and workers', { timeout: 120000 }, async (t) => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'haraka-renewal-'));
  const config = path.join(root, 'config');
  const bundlePath = path.join(config, 'certs/tls.pem');
  fs.mkdirSync(path.dirname(bundlePath), { recursive: true });
  fs.copyFileSync(path.join(__dirname, '../config/tls.ini'), path.join(config, 'tls.ini'));
  fs.copyFileSync(path.join(__dirname, '../config/smtp_forward.ini'), path.join(config, 'smtp_forward.ini'));
  execFileSync('openssl', ['genpkey', '-genparam', '-algorithm', 'DH', '-pkeyopt', 'group:ffdhe2048',
    '-out', path.join(config, 'dhparams.pem')]);
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));

  const hostname = 'mail.example.test';
  const openssl = (...args) => execFileSync('openssl', args, { cwd: root, stdio: 'ignore' });
  openssl('req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '2',
    '-subj', '/CN=Test root', '-keyout', 'root.key', '-out', 'root.crt');
  openssl('req', '-newkey', 'rsa:2048', '-nodes', '-subj', '/CN=Test intermediate',
    '-keyout', 'intermediate.key', '-out', 'intermediate.csr');
  fs.writeFileSync(path.join(root, 'intermediate.ext'),
    'basicConstraints=critical,CA:TRUE,pathlen:0\nkeyUsage=critical,keyCertSign,cRLSign\n');
  openssl('x509', '-req', '-in', 'intermediate.csr', '-CA', 'root.crt', '-CAkey', 'root.key',
    '-set_serial', '10', '-days', '2', '-extfile', 'intermediate.ext', '-out', 'intermediate.crt');
  fs.writeFileSync(path.join(root, 'leaf.ext'),
    `basicConstraints=critical,CA:FALSE\nsubjectAltName=DNS:${hostname}\nextendedKeyUsage=serverAuth\n`);
  const intermediate = fs.readFileSync(path.join(root, 'intermediate.crt'));
  const pairs = [1, 2, 3].map((serial) => {
    const key = path.join(root, `${serial}.key`);
    const cert = path.join(root, `${serial}.crt`);
    openssl('req', '-newkey', 'rsa:2048', '-nodes', '-subj', `/CN=${hostname}`,
      '-keyout', key, '-out', `${serial}.csr`);
    openssl('x509', '-req', '-in', `${serial}.csr`, '-CA', 'intermediate.crt',
      '-CAkey', 'intermediate.key', '-set_serial', String(serial), '-days', '2',
      '-extfile', 'leaf.ext', '-out', cert);
    const certificate = fs.readFileSync(cert);
    return {
      key: fs.readFileSync(key),
      cert: Buffer.concat([certificate, intermediate]),
      fingerprint: new X509Certificate(certificate).fingerprint256,
    };
  });
  const publish = (data) => {
    fs.writeFileSync(`${bundlePath}.tmp`, data);
    fs.renameSync(`${bundlePath}.tmp`, bundlePath);
  };
  const bundle = (pair) => Buffer.concat([pair.key, pair.cert]);

  // Use the installed Haraka and its real config watcher, not mocked reload APIs.
  const tlsSocket = require('Haraka/tls_socket');
  tlsSocket.config = require('haraka-config').module_config(root);
  tlsSocket.load_tls_ini();
  const errors = [];
  const reloads = [];
  const plugin = {
    ...require('../plugins/tls_cert_reload'),
    haraka_require: () => tlsSocket,
    loginfo: (message) => reloads.push(message),
    logerror: (message) => errors.push(message),
  };
  plugin.register();
  assert.equal(plugin._interval.hasRef(), false);
  t.after(() => plugin.shutdown());
  t.after(() => require('haraka-config/lib/watch').closeAll());
  // The shipped forwarder reads the same PEM after the reload plugin registers.
  const forwarder = {
    ...require('Haraka/plugins/queue/smtp_forward'),
    config: tlsSocket.config,
  };
  forwarder.load_smtp_forward_ini();

  const serverSockets = new Set();
  const server = tlsSocket.createServer((socket) => {
    serverSockets.add(socket);
    socket.on('close', () => serverSockets.delete(socket));
    socket.on('error', () => socket.destroy());
    socket.on('data', (data) => {
      if (socket.cleartext) return socket.write('250 OK\r\n');
      assert.equal(data.toString(), 'STARTTLS\r\n');
      socket.write('220 Ready to start TLS\r\n');
      socket.upgrade(() => {});
    });
  });
  t.after(async () => {
    for (const socket of serverSockets) socket.destroy();
    await new Promise((resolve) => server.close(resolve));
  });
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  const connect = async (sni) => {
    const socket = net.connect(server.address().port, '127.0.0.1');
    await once(socket, 'connect');
    socket.write('STARTTLS\r\n');
    const [response] = await once(socket, 'data');
    assert.match(response.toString(), /^220 /);
    const secured = tls.connect({
      socket,
      ca: fs.readFileSync(path.join(root, 'root.crt')),
      servername: sni ? hostname : undefined,
      checkServerIdentity: (_name, cert) => tls.checkServerIdentity(hostname, cert),
    });
    await once(secured, 'secureConnect');
    assert.equal(secured.authorized, true);
    return secured;
  };
  const waitFor = async (predicate) => {
    for (let i = 0; i < 100; i++) {
      if (predicate()) return;
      await delay(100);
    }
    assert.fail(`Certificate watcher did not complete: ${errors.join('; ')}`);
  };
  const checkCertificate = async (pair) => {
    for (const sni of [false, true]) {
      const socket = await connect(sni);
      assert.equal(socket.getPeerCertificate().fingerprint256, pair.fingerprint);
      socket.destroy();
    }
  };

  // The first manual cron run can create the PEM after Haraka has started.
  publish(bundle(pairs[0]));
  await waitFor(() => reloads.length === 1);
  await checkCertificate(pairs[0]);
  const existing = await connect(false);
  t.after(() => existing.destroy());

  publish(bundle(pairs[1]));
  await waitFor(() => reloads.length === 2);
  await checkCertificate(pairs[1]);
  forwarder.load_smtp_forward_ini();
  assert.equal(existing.getPeerCertificate().fingerprint256, pairs[0].fingerprint);
  existing.write('NOOP\r\n');
  const [response] = await once(existing, 'data');
  assert.equal(response.toString(), '250 OK\r\n');

  // A mismatched pair and a cert without its key must preserve the active pair.
  publish(Buffer.concat([pairs[2].key, pairs[0].cert]));
  await waitFor(() => errors.length === 1);
  await checkCertificate(pairs[1]);
  publish(pairs[2].cert);
  await waitFor(() => errors.length === 2);
  await checkCertificate(pairs[1]);
  await delay(2200);
  assert.equal(errors.length, 2, 'unchanged invalid input must not flood the log');

  // Recover after bad input, even after the forwarder replaced the callback slot.
  publish(bundle(pairs[2]));
  await waitFor(() => reloads.length === 3);
  await checkCertificate(pairs[2]);
  publish(bundle(pairs[2]));
  await delay(6500);
  assert.equal(reloads.length, 3, 'identical bytes must not trigger another reload');

  // Exercise the actual installed CLI, shipped plugin order, and two workers.
  const instance = path.join(root, 'instance');
  const instanceConfig = path.join(instance, 'config');
  fs.cpSync(path.join(__dirname, '../config'), instanceConfig, { recursive: true });
  fs.cpSync(path.join(__dirname, '../plugins'), path.join(instance, 'plugins'), { recursive: true });
  fs.mkdirSync(path.join(instanceConfig, 'certs'), { recursive: true });
  fs.copyFileSync(path.join(config, 'dhparams.pem'), path.join(instanceConfig, 'dhparams.pem'));
  fs.writeFileSync(path.join(instanceConfig, 'me'), hostname);
  fs.writeFileSync(path.join(instanceConfig, 'log.ini'), 'level=info\ntimestamps=false\n');
  // Avoid unrelated external DNSBL monitoring in this local SMTP fixture.
  fs.writeFileSync(path.join(instanceConfig, 'dns-list.ini'), '[main]\nzones[]=zen.spamhaus.org\nperiodic_checks=0\n');
  const portProbe = net.createServer();
  portProbe.listen(0, '127.0.0.1');
  await once(portProbe, 'listening');
  const port = portProbe.address().port;
  await new Promise((resolve) => portProbe.close(resolve));
  fs.writeFileSync(path.join(instanceConfig, 'smtp.ini'),
    `listen=127.0.0.1:${port}\nnodes=2\ngraceful_shutdown=true\nforce_shutdown_timeout=3\n`);
  const instanceBundle = path.join(instanceConfig, 'certs/tls.pem');
  fs.writeFileSync(instanceBundle, bundle(pairs[0]));
  const child = spawn(process.execPath, [require.resolve('Haraka/bin/haraka'), '-c', instance], {
    cwd: instance,
    env: { ...process.env, HARAKA: instance },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  let logs = '';
  child.stdout.on('data', (data) => { logs += data; });
  child.stderr.on('data', (data) => { logs += data; });
  t.after(async () => {
    if (child.exitCode !== null || child.signalCode !== null) return;
    child.kill('SIGINT');
    await once(child, 'exit');
  });
  const waitForLogs = async (predicate) => {
    for (let i = 0; i < 150; i++) {
      assert.equal(child.exitCode, null, logs);
      if (predicate()) return;
      await delay(100);
    }
    assert.fail(`Haraka workers did not complete:\n${logs}`);
  };
  await waitForLogs(() => /worker 1 listening/.test(logs) && /worker 2 listening/.test(logs));
  assert.match(logs, /loading queue\/smtp_forward/);
  const clients = new Set();
  t.after(() => { for (const client of clients) client.destroy(); });
  const readReply = async (socket) => {
    let reply = '';
    while (!/^\d{3} .*\r\n$/m.test(reply)) {
      const [data] = await once(socket, 'data');
      reply += data;
    }
    return reply;
  };
  const workerConnect = async (pair, sni) => {
    const socket = net.connect(port, '127.0.0.1');
    clients.add(socket);
    assert.match(await readReply(socket), /^220 /);
    socket.write(`EHLO ${hostname}\r\n`);
    assert.match(await readReply(socket), /250.STARTTLS/);
    socket.write('STARTTLS\r\n');
    assert.match(await readReply(socket), /^220 /);
    const secured = tls.connect({ socket, ca: fs.readFileSync(path.join(root, 'root.crt')),
      servername: sni ? hostname : undefined,
      checkServerIdentity: (_name, cert) => tls.checkServerIdentity(hostname, cert),
    });
    clients.add(secured);
    await once(secured, 'secureConnect');
    assert.equal(secured.authorized, true);
    assert.equal(secured.getPeerCertificate().fingerprint256, pair.fingerprint);
    return secured;
  };
  const held = await workerConnect(pairs[0], false);
  for (const [index, pair] of pairs.slice(1).entries()) {
    // Force a real forwarder config reload before each renewal.
    fs.appendFileSync(path.join(instanceConfig, 'smtp_forward.ini'), `\n; renewal ${index}\n`);
    await delay(5500);
    logs = '';
    fs.writeFileSync(`${instanceBundle}.tmp`, bundle(pair));
    fs.renameSync(`${instanceBundle}.tmp`, instanceBundle);
    // Each worker and the primary must independently activate the new bundle.
    await waitForLogs(() => (logs.match(/Reloaded SMTP TLS certificate bundle/g) || []).length === 3);
    for (const sni of [false, true]) {
      const secured = await workerConnect(pair, sni);
      secured.destroy();
    }
    held.write('NOOP\r\n');
    assert.match(await readReply(held), /^250 /);
  }
  held.destroy();
});
