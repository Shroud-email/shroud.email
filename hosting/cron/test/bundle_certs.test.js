'use strict';

const assert = require('node:assert/strict');
const { execFileSync, spawn } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { test } = require('node:test');

test('bundler atomically publishes a validated pair and preserves active versions on failure', async t => {
  const fixture = fs.mkdtempSync(path.join(os.tmpdir(), 'shroud-bundle-certs-'));
  t.after(() => fs.rmSync(fixture, { recursive: true, force: true }));
  const pem = path.join(fixture, 'pem');
  const caddy = path.join(fixture, 'caddy');
  const tlsIni = path.join(fixture, 'tls.ini');
  fs.mkdirSync(path.join(pem, 'versions/old'), { recursive: true });
  fs.mkdirSync(caddy);
  const certificate = name => {
    const key = path.join(fixture, `${name}.key`);
    const cert = path.join(fixture, `${name}.crt`);
    execFileSync('openssl', ['req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '2',
      '-subj', '/CN=mail.example', '-keyout', key, '-out', cert], { stdio: 'ignore' });
    return { key: fs.readFileSync(key), cert: fs.readFileSync(cert) };
  };
  const first = certificate('first');
  const second = certificate('second');
  fs.writeFileSync(path.join(pem, 'versions/old/tls_key.pem'), first.key);
  fs.writeFileSync(path.join(pem, 'versions/old/tls_cert.pem'), first.cert);
  fs.symlinkSync('versions/old', path.join(pem, 'current'));
  fs.writeFileSync(tlsIni, 'fixture');
  fs.utimesSync(tlsIni, new Date(0), new Date(0));

  const env = { ...process.env, EMAIL_DOMAIN: 'mail.example', CADDY_CERT_DIR: caddy,
    PEM_DIR: pem, TLS_CONFIG: tlsIni };
  const script = path.join(__dirname, '../bundle_certs.sh');
  const run = () => execFileSync('bash', [script], { env, stdio: 'pipe' });
  fs.writeFileSync(path.join(caddy, 'mail.example.key'), first.key);
  for (const invalid of [second.cert, Buffer.from('malformed certificate')]) {
    fs.writeFileSync(path.join(caddy, 'mail.example.crt'), invalid);
    assert.throws(run);
    assert.equal(fs.readlinkSync(path.join(pem, 'current')), 'versions/old');
    assert.deepEqual(fs.readFileSync(path.join(pem, 'current/tls_cert.pem')), first.cert);
    assert.equal(fs.statSync(tlsIni).mtimeMs, 0);
  }

  fs.writeFileSync(path.join(caddy, 'mail.example.key'), second.key);
  fs.writeFileSync(path.join(caddy, 'mail.example.crt'), second.cert);
  const bin = path.join(fixture, 'bin');
  fs.mkdirSync(bin);
  const realMv = execFileSync('sh', ['-c', 'command -v mv'], { encoding: 'utf8' }).trim();
  fs.writeFileSync(path.join(bin, 'mv'), `#!/bin/sh\n"${realMv}" "$@"\nexit 1\n`, { mode: 0o755 });
  const originalPath = env.PATH;
  env.PATH = `${bin}:${originalPath}`;
  // Simulate an interruption immediately after the switch, before the reload trigger.
  assert.throws(run);
  assert.notEqual(fs.readlinkSync(path.join(pem, 'current')), 'versions/old');
  assert.deepEqual(fs.readFileSync(path.join(pem, 'current/tls_key.pem')), second.key);
  assert.deepEqual(fs.readFileSync(path.join(pem, 'current/tls_cert.pem')), second.cert);
  assert.equal(fs.statSync(tlsIni).mtimeMs, 0);
  const secondVersion = fs.readlinkSync(path.join(pem, 'current'));

  env.PATH = originalPath;
  run();
  // Unchanged content does not create another version, but recovers the reload.
  assert.equal(fs.readlinkSync(path.join(pem, 'current')), secondVersion);
  assert.deepEqual(fs.readFileSync(path.join(pem, 'current/tls_cert.pem')), second.cert);
  assert.ok(fs.statSync(tlsIni).mtimeMs > 0);
  assert.deepEqual(fs.readdirSync(pem).filter(name => name.startsWith('.current')), []);
  assert.deepEqual(fs.readdirSync(path.join(pem, 'versions')).sort(),
    ['old', path.basename(secondVersion)].sort());

  // Another renewal retains the immediate previous pair, not all historical keys.
  fs.writeFileSync(path.join(caddy, 'mail.example.key'), first.key);
  fs.writeFileSync(path.join(caddy, 'mail.example.crt'), first.cert);
  run();
  const currentVersion = fs.readlinkSync(path.join(pem, 'current'));
  assert.notEqual(currentVersion, secondVersion);
  const expectedVersions = [path.basename(currentVersion), path.basename(secondVersion)].sort();
  assert.deepEqual(fs.readdirSync(path.join(pem, 'versions')).sort(), expectedVersions);
  for (let dailyRun = 0; dailyRun < 3; dailyRun++) run();
  assert.equal(fs.readlinkSync(path.join(pem, 'current')), currentVersion);
  assert.deepEqual(fs.readdirSync(path.join(pem, 'versions')).sort(), expectedVersions);

  // Hold one run after publication while a second run starts. Without a lock
  // around publication and pruning, the first run's stale current_version can
  // prune the second run's newly active directory.
  const pauseClaim = path.join(fixture, 'pause-claim');
  const pauseEntered = path.join(fixture, 'pause-entered');
  const pauseRelease = path.join(fixture, 'pause-release');
  const flockClaim = path.join(fixture, 'flock-claim');
  const secondAtLock = path.join(fixture, 'second-at-lock');
  const realTouch = execFileSync('sh', ['-c', 'command -v touch'], { encoding: 'utf8' }).trim();
  const realFlock = execFileSync('sh', ['-c', 'command -v flock'], { encoding: 'utf8' }).trim();
  fs.rmSync(path.join(bin, 'mv'));
  fs.writeFileSync(path.join(bin, 'touch'), `#!/bin/sh
if mkdir "$PAUSE_CLAIM" 2>/dev/null; then
  "${realTouch}" "$PAUSE_ENTERED"
  while [ ! -e "$PAUSE_RELEASE" ]; do sleep 0.01; done
fi
exec "${realTouch}" "$@"
`, { mode: 0o755 });
  fs.writeFileSync(path.join(bin, 'flock'), `#!/bin/sh
if ! mkdir "$FLOCK_CLAIM" 2>/dev/null; then "${realTouch}" "$SECOND_AT_LOCK"; fi
exec "${realFlock}" "$@"
`, { mode: 0o755 });
  env.PATH = `${bin}:${originalPath}`;
  Object.assign(env, { PAUSE_CLAIM: pauseClaim, PAUSE_ENTERED: pauseEntered,
    PAUSE_RELEASE: pauseRelease, FLOCK_CLAIM: flockClaim, SECOND_AT_LOCK: secondAtLock });

  const runAsync = () => new Promise((resolve, reject) => {
    const child = spawn('bash', [script], { env, stdio: 'pipe' });
    let stderr = '';
    child.stderr.on('data', chunk => { stderr += chunk; });
    child.on('error', reject);
    child.on('close', code => code === 0 ? resolve() : reject(new Error(stderr)));
  });
  const waitFor = async file => {
    for (let attempt = 0; attempt < 500; attempt++) {
      if (fs.existsSync(file)) return;
      await new Promise(resolve => setTimeout(resolve, 10));
    }
    throw new Error(`timed out waiting for ${file}`);
  };

  fs.writeFileSync(path.join(caddy, 'mail.example.key'), second.key);
  fs.writeFileSync(path.join(caddy, 'mail.example.crt'), second.cert);
  const firstRun = runAsync();
  let secondRun;
  try {
    await waitFor(pauseEntered);
    // Independently prove the publisher still holds the kernel lock before
    // pruning. This fails even if a competing process merely happens to finish
    // after it and would otherwise conceal the race.
    assert.throws(() => execFileSync(realFlock,
      ['-n', path.join(pem, '.bundle_certs.lock'), 'true']), { status: 1 });
    fs.writeFileSync(path.join(caddy, 'mail.example.key'), first.key);
    fs.writeFileSync(path.join(caddy, 'mail.example.crt'), first.cert);
    secondRun = runAsync();
    await waitFor(secondAtLock);
  } finally {
    // Release paused children even when a wait or assertion fails.
    fs.writeFileSync(pauseRelease, 'release');
    await Promise.all([firstRun, secondRun]);
  }

  const finalCurrent = fs.readlinkSync(path.join(pem, 'current'));
  assert.match(finalCurrent, /^versions\/tls\./);
  assert.deepEqual(fs.readFileSync(path.join(pem, 'current/tls_key.pem')), first.key);
  assert.deepEqual(fs.readFileSync(path.join(pem, 'current/tls_cert.pem')), first.cert);
  const retainedVersions = fs.readdirSync(path.join(pem, 'versions'));
  assert.ok(retainedVersions.includes(path.basename(finalCurrent)));
  assert.ok(retainedVersions.length <= 2, `retained ${retainedVersions.length} versions`);
});
