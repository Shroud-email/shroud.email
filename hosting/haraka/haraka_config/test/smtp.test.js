'use strict';

const assert = require('node:assert/strict');
const { execFileSync, spawn } = require('node:child_process');
const { once } = require('node:events');
const fs = require('node:fs');
const net = require('node:net');
const os = require('node:os');
const path = require('node:path');
const tls = require('node:tls');
const { test } = require('node:test');

// An isolated instance without node_modules exercises the Compose mount layout.
test('Haraka CLI starts with the full plugin list and handles STARTTLS and AUTH', { timeout: 20000 }, async t => {
  const instance = fs.mkdtempSync(path.join(os.tmpdir(), 'shroud-haraka-smtp-'));
  fs.cpSync(path.join(__dirname, '../config'), path.join(instance, 'config'), { recursive: true });
  fs.symlinkSync(path.join(__dirname, '../plugins'), path.join(instance, 'plugins'));
  const config = path.join(instance, 'config');
  fs.writeFileSync(path.join(config, 'me'), 'mail.example\n');
  fs.appendFileSync(path.join(config, 'smtp.ini'), '\nlisten=127.0.0.1:0\n');
  fs.writeFileSync(path.join(config, 'log.ini'), 'level=notice\n');
  // Do not run periodic public DNS health checks during the smoke test.
  fs.appendFileSync(path.join(config, 'dns-list.ini'), '\n[main]\nperiodic_checks=0\n');
  fs.mkdirSync(path.join(config, 'certs'), { recursive: true });
  execFileSync('openssl', ['req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '2',
    '-subj', '/CN=mail.example', '-addext', 'subjectAltName=DNS:mail.example',
    '-keyout', path.join(config, 'certs/tls_key.pem'), '-out', path.join(config, 'certs/tls_cert.pem')], { stdio: 'ignore' });
  execFileSync('openssl', ['genpkey', '-genparam', '-algorithm', 'DH', '-pkeyopt', 'group:ffdhe2048', '-out', path.join(config, 'dhparams.pem')]);

  const child = spawn(process.execPath, [require.resolve('Haraka/bin/haraka'), '-c', instance], {
    env: { ...process.env, SMTP_USERNAME: 'relay-user', SMTP_PASSWORD: 'test-only-password' },
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  const exited = once(child, 'exit');
  t.after(async () => {
    child.kill('SIGTERM');
    await exited;
    fs.rmSync(instance, { recursive: true, force: true });
  });
  let output = '';
  let completed = false;
  t.after(() => { if (!completed) t.diagnostic(output); });
  const port = await new Promise((resolve, reject) => {
    child.on('error', reject);
    child.once('exit', code => reject(new Error(`Haraka exited ${code}: ${output}`)));
    function collect(chunk) {
      output += chunk.toString();
      const match = output.match(/Listening on \[?127\.0\.0\.1\]?:(\d+)/);
      if (match) resolve(Number(match[1]));
    }
    child.stdout.on('data', collect);
    child.stderr.on('data', collect);
  });

  function reply(socket, command) {
    return new Promise((resolve, reject) => {
      let buffer = '';
      function data(chunk) {
        buffer += chunk.toString();
        if (!/\r\n$/.test(buffer) || !/^\d{3} /m.test(buffer)) return;
        socket.removeListener('data', data);
        socket.removeListener('error', reject);
        resolve(buffer);
      }
      socket.on('data', data);
      socket.once('error', reject);
      if (command) socket.write(`${command}\r\n`);
    });
  }
  const socket = net.connect({ host: '127.0.0.1', port });
  t.after(() => socket.destroy());
  assert.match(await reply(socket), /^220 /);
  assert.match(await reply(socket, 'EHLO client.example'), /250[- ]STARTTLS/);
  assert.match(await reply(socket, 'STARTTLS'), /^220 /);
  const secure = tls.connect({ socket, servername: 'mail.example', rejectUnauthorized: false });
  t.after(() => secure.destroy());
  await once(secure, 'secureConnect');
  assert.equal(tls.checkServerIdentity('mail.example', secure.getPeerCertificate()), undefined);
  const capabilities = await reply(secure, 'EHLO client.example');
  assert.match(capabilities, /AUTH CRAM-MD5 PLAIN LOGIN/);
  assert.doesNotMatch(capabilities, /STARTTLS/);
  const credentials = Buffer.from('\0relay-user\0test-only-password').toString('base64');
  assert.match(await reply(secure, `AUTH PLAIN ${credentials}`), /^235 /);
  assert.match(await reply(secure, 'QUIT'), /^221 /);
  completed = true;
});
