'use strict'

const assert = require('node:assert/strict')
const {execFileSync} = require('node:child_process')
const Module = require('node:module')
const {afterEach, test} = require('node:test')

const verified_domains_query = `SELECT domain FROM custom_domains
WHERE ownership_verified_at > (CURRENT_TIMESTAMP AT TIME ZONE 'UTC') - INTERVAL '1 day'
  AND mx_verified_at > (CURRENT_TIMESTAMP AT TIME ZONE 'UTC') - INTERVAL '1 day'
  AND spf_verified_at > (CURRENT_TIMESTAMP AT TIME ZONE 'UTC') - INTERVAL '1 day'
  AND dkim_verified_at > (CURRENT_TIMESTAMP AT TIME ZONE 'UTC') - INTERVAL '1 day'
  AND dmarc_verified_at > (CURRENT_TIMESTAMP AT TIME ZONE 'UTC') - INTERVAL '1 day'`

const plugin_path = require.resolve('../plugins/rcpt_to.host_list_base_shroud')
const original_load = Module._load

function load_plugin (query) {
    const pools = []

    Module._load = function (request, parent, is_main) {
        if (request !== 'pg') return original_load.call(this, request, parent, is_main)

        return {
            Pool: class {
                constructor (options) {
                    this.options = options
                    this.listeners = {}
                    pools.push(this)
                }

                on (event, listener) {
                    this.listeners[event] = listener
                }

                query (...args) {
                    query(...args)
                }
            },
        }
    }

    delete require.cache[plugin_path]
    return {plugin: require(plugin_path), pools}
}

afterEach(() => {
    Module._load = original_load
    delete require.cache[plugin_path]
    delete process.env.EMAIL_DOMAIN
})

test('shares one bounded pool across host-list loads', async () => {
    const queries = []
    const {plugin, pools} = load_plugin((sql, cb) => queries.push({sql, cb}))
    const context = {logerror: () => assert.fail('unexpected error')}
    const loaded = []

    plugin.load_host_list.call(context, domains => loaded.push(domains))
    plugin.load_host_list.call(context, domains => loaded.push(domains))

    assert.equal(pools.length, 1)
    assert.deepEqual(pools[0].options, {max: 10})
    assert.equal(queries.length, 2)
    assert.equal(queries[0].sql, verified_domains_query)

    queries[0].cb(null, {rows: [{domain: 'ONE.EXAMPLE'}]})
    queries[1].cb(null, {rows: [{domain: 'two.example'}]})
    assert.deepEqual([...loaded[0]], ['one.example'])
    assert.deepEqual([...loaded[1]], ['two.example'])
})

test('returns configured domain and logs query errors', () => {
    process.env.EMAIL_DOMAIN = 'LOCAL.EXAMPLE'
    const failure = new Error('database unavailable')
    const {plugin} = load_plugin((sql, cb) => cb(failure))
    const errors = []

    plugin.load_host_list.call({logerror: (...args) => errors.push(args)}, domains => {
        assert.deepEqual([...domains], ['local.example'])
    })

    assert.equal(errors.length, 1)
    assert.equal(errors[0][0], 'Failed to load host list! ')
})

test('handles idle pooled-client errors instead of leaving them unhandled', () => {
    const {plugin, pools} = load_plugin((sql, cb) => cb(null, {rows: []}))
    const errors = []
    plugin.load_host_list.call({logerror: (...args) => errors.push(args)}, () => {})

    pools[0].listeners.error(new Error('idle client failed'))

    assert.equal(errors.length, 1)
    assert.equal(errors[0][0], 'Host list database pool error! ')
})

test('database predicate matches fully_verified? timestamp semantics', {
    skip: process.env.TEST_DATABASE_URL == null && process.env.DATABASE_URL == null,
}, async () => {
    const sql = `WITH custom_domains(
        domain, ownership_verified_at, mx_verified_at, spf_verified_at,
        dkim_verified_at, dmarc_verified_at
    ) AS (VALUES
        ('verified.example', CURRENT_TIMESTAMP AT TIME ZONE 'UTC', CURRENT_TIMESTAMP AT TIME ZONE 'UTC', CURRENT_TIMESTAMP AT TIME ZONE 'UTC', CURRENT_TIMESTAMP AT TIME ZONE 'UTC', CURRENT_TIMESTAMP AT TIME ZONE 'UTC'),
        ('stale.example', CURRENT_TIMESTAMP AT TIME ZONE 'UTC', CURRENT_TIMESTAMP AT TIME ZONE 'UTC', CURRENT_TIMESTAMP AT TIME ZONE 'UTC' - INTERVAL '1 day', CURRENT_TIMESTAMP AT TIME ZONE 'UTC', CURRENT_TIMESTAMP AT TIME ZONE 'UTC'),
        ('missing.example', CURRENT_TIMESTAMP AT TIME ZONE 'UTC', CURRENT_TIMESTAMP AT TIME ZONE 'UTC', CURRENT_TIMESTAMP AT TIME ZONE 'UTC', CURRENT_TIMESTAMP AT TIME ZONE 'UTC', NULL)
    ) ${verified_domains_query}`
    const output = execFileSync('psql', [
        process.env.TEST_DATABASE_URL || process.env.DATABASE_URL,
        '--no-align', '--tuples-only', '--command', sql,
    ], {encoding: 'utf8'})

    assert.equal(output.trim(), 'verified.example')
})
