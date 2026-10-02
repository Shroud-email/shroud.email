'use strict'

const fs = require('node:fs/promises')
const path = require('node:path')

const { parseHeader } = require('@haraka/email-address')

const dkim = require('./lib/dkim')

const { DKIMVerifyStream, DKIMSignStream } = dkim

exports.register = function () {
  const plugin = this
  this.load_dkim_ini()

  dkim.DKIMObject.prototype.debug = (str) => {
    plugin.logdebug(str)
  }

  DKIMVerifyStream.prototype.debug = (str) => {
    plugin.logdebug(str)
  }

  if (this.cfg.verify.enabled) {
    this.register_hook('data_post', 'dkim_verify')
  }

  if (this.cfg.sign.enabled) {
    this.register_hook('queue_outbound', 'hook_pre_send_trans_email')
  }
}

exports.load_dkim_ini = function () {
  this.cfg = this.config.get(
    'dkim.ini',
    {
      booleans: ['-sign.enabled', '+verify.enabled'],
    },
    () => {
      this.load_dkim_ini()
    },
  )

  if (this.cfg.verify === undefined) this.cfg.verify = {}
  if (!this.cfg.verify.timeout) {
    this.cfg.verify.timeout = this.timeout ? this.timeout - 1 : 29
  }

  this.load_dkim_default_key()
  this.cfg.headers_to_sign = this.get_headers_to_sign()
}

exports.load_dkim_default_key = function () {
  this.private_key = this.config
    .get('dkim.private.key', 'data', () => {
      this.load_dkim_default_key()
    })
    .join('\n')
}

exports.load_key = function (file) {
  return this.config.get(file, 'data').join('\n')
}

exports.hook_pre_send_trans_email = function (next, connection) {
  if (!this.cfg.sign.enabled) return next()
  if (!connection?.transaction) return next()

  if (connection.transaction.notes?.dkim_signed) {
    connection.logdebug(this, 'already signed')
    return next()
  }

  this.sign_message(connection, next).catch((err) => {
    connection.logerror(this, `${err.message}`)
    next()
  })
}

exports.sign_message = async function (connection, next) {
  const props = await this.get_sign_properties(connection)

  if (!connection?.transaction) return next()
  if (!props || !this.has_key_data(connection, props)) return next()

  connection.logdebug(this, `domain: ${props.domain}`)

  const txn = connection.transaction
  props.headers = this.cfg.headers_to_sign
  props.body_canon = this.cfg.canon?.body || 'simple'

  try {
    const dkim_header = await this.run_sign_stream(txn, props)
    connection.loginfo(this, `signed for ${props.domain}`)
    txn.results.add(this, { pass: dkim_header })
    txn.add_header('DKIM-Signature', dkim_header)
    connection.transaction.notes.dkim_signed = true
    // Defensive unpipe — see haraka/message-stream#22.
    txn.message_stream.unpipe()
    next()
  } catch (err) {
    txn.results.add(this, { err: err.message })
    txn.message_stream.unpipe()
    next(err)
  }
}

exports.run_sign_stream = function (txn, props) {
  return new Promise((resolve, reject) => {
    txn.message_stream.pipe(
      new DKIMSignStream(props, txn.header, (err, dkim_header) => {
        if (err) return reject(err)
        resolve(dkim_header)
      }),
      {}, // options
    )
  })
}

exports.get_sign_properties = async function (connection) {
  if (!connection.transaction) return

  const domain = this.get_sender_domain(connection)

  if (!domain) {
    connection.transaction.results.add(this, {
      msg: 'sending domain not detected',
      emit: true,
    })
  }

  const props = { domain }

  let keydir
  try {
    keydir = await this.get_key_dir(connection, domain)
  } catch (err) {
    connection.logerror(
      this,
      `Error getting DKIM key_dir for ${domain}: ${err}`,
    )
    return props
  }

  if (!connection.transaction) return props

  // a directory for ${domain} exists
  if (keydir) {
    props.domain = path.basename(keydir) // keydir might be apex (vs sub)domain
    props.private_key = this.load_key(
      path.join('dkim', props.domain, 'private'),
    )
    props.selector = this.load_key(
      path.join('dkim', props.domain, 'selector'),
    ).trim()

    if (!props.selector) {
      connection.transaction.results.add(this, {
        err: `missing selector for domain ${domain}`,
      })
    }
    if (!props.private_key) {
      connection.transaction.results.add(this, {
        err: `missing dkim private_key for domain ${domain}`,
      })
    }

    // AND has correct files
    if (props.selector && props.private_key) return props
  }

  // try [default / single domain] configuration
  if (this.cfg.sign.domain && this.cfg.sign.selector && this.private_key) {
    connection.transaction.results.add(this, {
      msg: 'using default key',
      emit: true,
    })

    props.domain = this.cfg.sign.domain
    props.private_key = this.private_key
    props.selector = this.cfg.sign.selector

    return props
  }

  connection.transaction?.results.add(this, {
    err: 'no valid DKIM properties found',
  })
  return props
}

// Resolve the most specific config/dkim/<domain> directory that exists,
// walking from the full host up the label hierarchy (e.g. mail.example.com,
// then example.com). The walk stops at two labels so we never match a
// single-label TLD directory like config/dkim/com/. Admins who need
// public-suffix-aware behavior (e.g. distinguishing example.co.uk from
// co.uk) should configure explicit per-domain directories.
exports.get_key_dir = async function (connection, domain) {
  if (!domain) return

  const haraka_dir = process.env.HARAKA || ''
  const labels = domain.split('.')

  // i <= labels.length - 2 keeps at least 2 labels in the candidate.
  for (let i = 0; i <= labels.length - 2; i++) {
    const filePath = path.resolve(
      haraka_dir,
      'config',
      'dkim',
      labels.slice(i).join('.'),
    )
    try {
      const stats = await fs.stat(filePath)
      if (stats.isDirectory()) {
        connection.logdebug(this, filePath)
        return filePath
      }
    } catch {
      // not found / not accessible — try the next, less specific label
    }
  }

  connection.logdebug(this, undefined)
}

exports.has_key_data = function (conn, props) {
  let missing = undefined

  // Make sure we have all the relevant configuration
  if (!props.private_key) {
    missing = 'private key'
  } else if (!props.selector) {
    missing = 'selector'
  } else if (!props.domain) {
    missing = 'domain'
  }

  if (missing) {
    if (props.domain) {
      conn.lognotice(this, `skipped: no ${missing} for ${props.domain}`)
    } else {
      conn.lognotice(this, `skipped: no ${missing}`)
    }
    return false
  }

  conn.logprotocol(
    this,
    `using selector: ${props.selector} at domain ${props.domain}`,
  )
  return true
}

exports.get_headers_to_sign = function () {
  if (!this.cfg?.sign?.headers) return ['from']

  const headers = this.cfg.sign.headers
    .toLowerCase()
    .replace(/\s+/g, '')
    .split(/[,;:]/)

  // From MUST be present
  if (!headers.includes('from')) headers.push('from')

  return headers
}

exports.get_sender_domain = function (connection) {
  const txn = connection?.transaction
  if (!txn) return

  // fallback: use the Envelope FROM when From header parsing fails
  const envelope_domain = this.envelope_domain(connection, txn)

  // In case of forwarding, only use the Envelope
  if (txn.notes.forward) return envelope_domain
  if (!txn.header) return envelope_domain

  // The DKIM signing key should be aligned with the domain in the From
  // header (see DMARC). Try to parse the domain from there.
  // Use the raw header: RFC 2047 encoded-words exist so that specials like
  // commas survive inside a display-name.
  const from_hdr = txn.header.get('From')
  if (!from_hdr) return envelope_domain

  // The From header can contain multiple addresses and should be
  // parsed as described in RFC 2822 3.6.2.
  const addrs = this.parse_address_header(connection, from_hdr)
  if (!addrs || !addrs.length) return envelope_domain

  // If From has a single, resolvable address, we're done
  if (addrs.length === 1 && addrs[0].host) {
    return addrs[0].host.toLowerCase()
  }

  // Multiple addresses (or an unresolvable group): use the domain in the
  // Sender header, falling back to the Envelope.
  return this.sender_header_domain(connection, txn) ?? envelope_domain
}

exports.envelope_domain = function (connection, txn) {
  if (!txn.mail_from?.host) return
  try {
    return txn.mail_from.host.toLowerCase()
  } catch (e) {
    connection.logerror(this, e)
  }
}

exports.parse_address_header = function (connection, hdr) {
  try {
    return parseHeader(hdr)
  } catch (ignore) {
    connection.logerror(
      this,
      `@haraka/email-address failed to parse From header: ${hdr}`,
    )
  }
}

exports.sender_header_domain = function (connection, txn) {
  const sender = txn.header.get('Sender')
  if (!sender) return
  try {
    return parseHeader(sender)?.[0]?.host?.toLowerCase()
  } catch (e) {
    connection.logerror(this, e)
  }
}

exports.dkim_verify = function (next, connection) {
  if (!this.cfg.verify.enabled) return next()

  const txn = connection?.transaction
  if (!txn) return next()

  this.verify_message(connection, txn).then(
    (args) => {
      // Defensive unpipe — see haraka/message-stream#22.
      txn.message_stream.unpipe()
      next(...args)
    },
    (err) => {
      txn.results.add(this, { err })
      txn.message_stream.unpipe()
      next()
    },
  )
}

exports.run_verify_stream = function (txn) {
  return new Promise((resolve, reject) => {
    const verifier = new DKIMVerifyStream(
      this.cfg.verify,
      (err, result, results) => {
        if (err) return reject(err)
        resolve(results)
      },
    )
    txn.message_stream.pipe(verifier, { line_endings: '\r\n' })
  })
}

// Runs verification and records results. Resolves to the args array to
// pass to next() (empty, or [CONT, 'no/bad signature']).
exports.verify_message = async function (connection, txn) {
  const results = await this.run_verify_stream(txn)

  if (!results || results.length === 0) {
    txn.results.add(this, { skip: 'no/bad signature' })
    return [CONT, 'no/bad signature']
  }

  connection.logdebug(this, JSON.stringify(results))
  txn.notes.dkim_results = results // Store results for other plugins

  for (const res of results) {
    let res_err = ''
    if (res.error) res_err = ` (${res.error})`
    connection.auth_results(
      `dkim=${res.result}${res_err} header.i=${res.identity} header.d=${res.domain} header.s=${res.selector}`,
    )
    connection.loginfo(
      this,
      `identity="${res.identity}" domain="${res.domain}" selector="${res.selector}" result=${res.result} ${res_err}`,
    )

    // save to ResultStore
    const rs_tidy = {
      domain: res.domain,
      identity: res.identity,
      selector: res.selector,
    }

    if (res.result === 'pass') rs_tidy.pass = res.domain
    if (res.result === 'fail') rs_tidy.fail = res.domain
    if (res.error) rs_tidy.err = res.error

    txn.results.add(this, rs_tidy)
  }

  return []
}
