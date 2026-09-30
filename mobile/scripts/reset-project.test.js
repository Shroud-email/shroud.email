const assert = require('node:assert/strict');
const { spawnSync } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { test } = require('node:test');

function fixture(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'shroud-reset-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  fs.mkdirSync(path.join(root, 'src'));
  fs.writeFileSync(path.join(root, 'src', 'original.txt'), 'original source');
  fs.mkdirSync(path.join(root, 'scripts'));
  fs.copyFileSync(require.resolve('./reset-project.js'), path.join(root, 'scripts/reset-project.js'));
  return root;
}

function reset(root, input) {
  return spawnSync(process.execPath, ['scripts/reset-project.js'], {
    cwd: root,
    input,
    encoding: 'utf8',
  });
}

test('archiving preserves the source and keeps the reset command available', (t) => {
  const root = fixture(t);
  const result = reset(root, '\n');
  assert.equal(result.status, 0, result.stderr);
  assert.equal(fs.readFileSync(path.join(root, 'example/src/original.txt'), 'utf8'), 'original source');
  assert.match(fs.readFileSync(path.join(root, 'src/app/index.tsx'), 'utf8'), /export default function Index/);
  assert.match(fs.readFileSync(path.join(root, 'src/app/_layout.tsx'), 'utf8'), /<Stack/);
  assert.ok(fs.existsSync(path.join(root, 'scripts/reset-project.js')));
});

test('deleting source keeps the reset command usable for another reset', (t) => {
  const root = fixture(t);
  assert.equal(reset(root, 'n\n').status, 0);
  assert.ok(!fs.existsSync(path.join(root, 'example')));
  assert.ok(!fs.existsSync(path.join(root, 'src/original.txt')));
  assert.equal(reset(root, 'n\n').status, 0);
  assert.ok(fs.existsSync(path.join(root, 'src/app/index.tsx')));
});

test('an archive collision fails without overwriting existing or current source', (t) => {
  const root = fixture(t);
  fs.mkdirSync(path.join(root, 'example/src'), { recursive: true });
  fs.writeFileSync(path.join(root, 'example/src/archived.txt'), 'previous archive');
  const result = reset(root, 'y\n');
  assert.equal(result.status, 1);
  assert.match(result.stderr, /Error during script execution/);
  assert.equal(fs.readFileSync(path.join(root, 'src/original.txt'), 'utf8'), 'original source');
  assert.equal(fs.readFileSync(path.join(root, 'example/src/archived.txt'), 'utf8'), 'previous archive');
  assert.ok(!fs.existsSync(path.join(root, 'src/app/index.tsx')));
});
