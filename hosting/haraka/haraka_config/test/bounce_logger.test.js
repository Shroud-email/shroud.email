'use strict'

const assert = require('node:assert/strict')
const {test} = require('node:test')

const plugin = require('../plugins/bounce_logger')

test('logs a bounce through the bound plugin and continues', () => {
    const warnings = []
    let next_calls = 0
    const context = {logwarn: message => warnings.push(message)}

    plugin.hook_bounce.call(context, () => { next_calls++ }, {}, 'mailbox unavailable')

    assert.deepEqual(warnings, ['Bounced message: mailbox unavailable'])
    assert.equal(next_calls, 1)
})
