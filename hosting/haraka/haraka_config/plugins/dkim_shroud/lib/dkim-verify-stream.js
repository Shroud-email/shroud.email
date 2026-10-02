'use strict'

const { Stream } = require('node:stream')
const utils = require('haraka-utils')

const DKIMObject = require('./dkim-object')

class Buf {
  constructor() {
    this.bar = []
    this.blen = 0
  }

  pop(buf = Buffer.from('')) {
    if (!this.bar.length) return buf
    if (buf.length) {
      this.bar.push(buf)
      this.blen += buf.length
    }
    const nb = Buffer.concat(this.bar, this.blen)
    this.bar = []
    this.blen = 0
    return nb
  }

  push(buf) {
    if (buf.length) {
      this.bar.push(buf)
      this.blen += buf.length
    }
  }
}

class DKIMVerifyStream extends Stream {
  constructor(opts, cb) {
    super()
    this.run_cb = false
    this.cb = (err, result, results) => {
      if (!this.run_cb) {
        this.run_cb = true
        return cb(err, result, results)
      }
    }
    this._in_body = false
    this._no_signatures_found = false
    this.buffer = new Buf()
    this.headers = []
    this.header_idx = {}
    this.dkim_objects = []
    this.results = []
    this.result = 'none'
    this.pending = 0
    this.writable = true
    this.opts = opts
    this.header_size = 0
    this.max_header_size = Number(process.env.MAX_HEADER_SIZE) || 1024 * 1024 // Default 1MB
  }

  debug(str) {
    console.debug(str)
  }

  // Result callback handed to each DKIMObject. Aggregates per-signature
  // results and fires the stream callback once all are in.
  #onSignatureResult(err, result) {
    this.pending--
    if (result) {
      const results = {
        identity: result.identity,
        domain: result.domain,
        selector: result.selector,
        result: result.result,
      }
      if (err) {
        results.error = err.message
        if (this.opts.sigerror_log_level)
          results.emit_log_level = this.opts.sigerror_log_level
      }
      this.results.push(results)

      // Set the overall result using priority order: earlier entries win.
      // RFC 6376 §6.1: take the most favorable result across all signatures.
      const rr = ['pass', 'tempfail', 'fail', 'invalid', 'none']
      const currentIdx = rr.indexOf(this.result)
      const newIdx = rr.indexOf(result.result)
      if (newIdx < currentIdx) {
        this.result = result.result
      }
    }

    this.debug(JSON.stringify(result))

    if (this.pending === 0 && this.cb) {
      return process.nextTick(() => {
        this.cb(null, this.result, this.results)
      })
    }
  }

  // Build header_idx (lower-cased header name → [raw header, ...]) from the
  // accumulated header lines.
  #indexHeaders() {
    for (const header of this.headers) {
      const match = /^([^: ]+):\s*((:?.|[\r\n])*)/.exec(header)
      if (!match) continue
      const header_name = match[1]
      if (!header_name) continue
      const hn = header_name.toLowerCase()
      if (!this.header_idx[hn]) this.header_idx[hn] = []
      this.header_idx[hn].push(header)
    }
  }

  #createDkimObjects() {
    const dkim_headers = this.header_idx['dkim-signature']
    this.debug(`Found ${dkim_headers.length} DKIM signatures`)
    this.pending = dkim_headers.length
    for (const dkimHeader of dkim_headers) {
      this.dkim_objects.push(
        new DKIMObject(
          dkimHeader,
          this.header_idx,
          (err, result) => this.#onSignatureResult(err, result),
          this.opts,
        ),
      )
    }
  }

  #accumulateHeaderLine(line) {
    if (line[0] === 0x20 || line[0] === 0x09) {
      // Header continuation
      this.headers[this.headers.length - 1] += line.toString('utf-8')
    } else {
      this.headers.push(line.toString('utf-8'))
    }
  }

  handle_buf(buf) {
    // Abort any further processing if the headers
    // did not contain any DKIM-Signature fields.
    if (this._in_body && this._no_signatures_found) {
      return true
    }
    let once = false
    if (buf === null) {
      once = true
      buf = this.buffer.pop()
      if (buf && buf[buf.length - 2] === 0x0d && buf[buf.length - 1] === 0x0a) {
        return true
      }
      buf = Buffer.concat([buf, Buffer.from('\r\n\r\n')])
    } else {
      buf = this.buffer.pop(buf)
    }

    // Process input buffer into lines
    let offset = 0
    while ((offset = utils.indexOfLF(buf)) !== -1) {
      let line = buf.slice(0, offset + 1)
      if (buf.length > offset) {
        buf = buf.slice(offset + 1)
      }

      // Check for LF line endings and convert to CRLF if necessary
      if (line[line.length - 2] !== 0x0d) {
        line = Buffer.concat(
          [line.slice(0, line.length - 1), Buffer.from('\r\n')],
          line.length + 1,
        )
      }

      // End-of-headers marker (a bare CRLF)
      if (
        line.length === 2 &&
        line[0] === 0x0d &&
        line[1] === 0x0a &&
        !this._in_body
      ) {
        this._in_body = true
        this.#indexHeaders()
        if (!this.header_idx['dkim-signature']) {
          this._no_signatures_found = true
          return process.nextTick(() => {
            this.cb(null, this.result, this.results)
          })
        }
        this.#createDkimObjects()
        if (this.pending === 0) {
          process.nextTick(() => {
            if (this.cb) this.cb(new Error('no signatures found'))
          })
        }
        continue // while()
      }

      if (!this._in_body) {
        // Parse headers
        this.header_size += line.length
        if (this.header_size > this.max_header_size) {
          return this.cb(new Error('maximum header size exceeded'))
        }
        this.#accumulateHeaderLine(line)
      } else {
        for (const dkimObject of this.dkim_objects) {
          dkimObject.add_body_line(line)
        }
      }
      if (once) {
        break
      }
    }

    this.buffer.push(buf)
    return true
  }

  write(buf) {
    return this.handle_buf(buf)
  }

  end(buf) {
    this.handle_buf(buf ?? null)
    for (const dkimObject of this.dkim_objects) {
      dkimObject.end()
    }
    if (this.pending === 0 && !this._no_signatures_found) {
      process.nextTick(() => {
        this.cb(null, this.result, this.results)
      })
    }
  }
}

module.exports = DKIMVerifyStream
