const assert = require('node:assert/strict');
const { test } = require('node:test');
const { filterAliases, createAlias, aliasesReducer } = require('../src/data/aliases.ts');

const aliases = [
  { id: 'one', address: 'abc@fog.shroud.email', title: 'Linear', notes: 'Work projects', enabled: true, forwarded: 48, forwardedThisMonth: 11 },
  { id: 'two', address: 'shop@mail.example.com', title: 'Shopping', notes: '', enabled: false, forwarded: 7, forwardedThisMonth: 0 },
  { id: 'three', address: 'empty@fog.shroud.email', title: null, notes: null, enabled: true, forwarded: 2, forwardedThisMonth: 1 },
];
const domains = [
  { name: 'mail.example.com', verified: true },
  { name: 'pending.example.com', verified: false },
];

test('search matches address, title or notes case-insensitively and intersects the status filter', () => {
  assert.deepEqual(filterAliases(aliases, ' WORK ', 'enabled').map(a => a.id), ['one']);
  assert.deepEqual(filterAliases(aliases, 'LINEAR', 'enabled').map(a => a.id), ['one']);
  assert.deepEqual(filterAliases(aliases, 'SHOP', 'enabled'), []);
  assert.deepEqual(filterAliases(aliases, 'MAIL.EXAMPLE', 'disabled').map(a => a.id), ['two']);
  assert.deepEqual(filterAliases(aliases, '', 'enabled').map(a => a.id), ['one', 'three']);
  assert.deepEqual(filterAliases(aliases, 'missing', 'all'), []);
});

test('custom creation normalizes the name and cannot use an unverified or unknown domain', () => {
  const alias = createAlias(aliases, domains, { type: 'custom', name: ' Receipts ', domain: 'mail.example.com' }, 'new-id');
  assert.equal(alias.address, 'receipts@mail.example.com');
  assert.equal(alias.enabled, true);
  assert.equal(alias.title, null);
  assert.equal(alias.forwarded, 0);
  for (const domain of ['pending.example.com', 'other.example.com']) {
    assert.throws(() => createAlias(aliases, domains, { type: 'custom', name: 'receipts', domain }, 'new-id'), /verified domain/i);
  }
});

test('custom creation rejects missing names, malformed names and existing addresses', () => {
  for (const name of ['', ' ', 'has space', 'has_underscore', 'a@b', 'a/b']) {
    assert.throws(() => createAlias(aliases, domains, { type: 'custom', name, domain: 'mail.example.com' }, 'new-id'), /alias name/i);
  }
  assert.throws(() => createAlias(aliases, domains, { type: 'custom', name: 'SHOP', domain: 'mail.example.com' }, 'new-id'), /already exists/i);
});

test('random creation ignores custom fields and uses a unique generated service address', () => {
  const alias = createAlias(aliases, domains, { type: 'random', name: 'ignored', domain: 'pending.example.com' }, '9a725c83-d134-4567-aaaa-bbbbbbbbbbbb');
  assert.equal(alias.address, '9a725c83d13445@fog.shroud.email');
  assert.equal(alias.id, '9a725c83-d134-4567-aaaa-bbbbbbbbbbbb');
});

test('edits clear empty fields without changing the address or other aliases', () => {
  const result = aliasesReducer(aliases, { type: 'update', id: 'one', changes: { title: '  ', notes: ' New notes ' } });
  assert.equal(result[0].title, null);
  assert.equal(result[0].notes, 'New notes');
  assert.equal(result[0].address, 'abc@fog.shroud.email');
  assert.equal(result[1], aliases[1]);
  assert.equal(aliases[0].title, 'Linear');
  assert.equal(aliasesReducer(result, { type: 'update', id: 'one', changes: { notes: '' } })[0].notes, null);
});

test('toggle, create and delete change only the intended alias and preserve the original collection', () => {
  const toggled = aliasesReducer(aliases, { type: 'toggle', id: 'two' });
  assert.equal(toggled[1].enabled, true);
  assert.equal(toggled[0], aliases[0]);
  assert.equal(aliases[1].enabled, false);
  const created = createAlias(aliases, domains, { type: 'custom', name: 'new', domain: 'mail.example.com' }, 'four');
  const added = aliasesReducer(toggled, { type: 'create', alias: created });
  assert.equal(added[0].address, 'new@mail.example.com');
  assert.deepEqual(aliasesReducer(added, { type: 'delete', id: 'one' }).map(a => a.id), ['four', 'two', 'three']);
  assert.equal(aliases.length, 3);
});
