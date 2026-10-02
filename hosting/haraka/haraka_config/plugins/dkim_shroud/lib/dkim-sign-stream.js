'use strict'

const crypto = require('node:crypto')
const { Stream } = require('node:stream')
const utils = require('haraka-utils')

class DKIMSignStream extends Stream {
  constructor(props, header, done) {
    super()

    this.selector = props.selector

    // fix issue #2668 renaming reserved kw/property of 'domain' to 'domain_name'
    this.domain_name = props.domain
    this.private_key = props.private_key
    this.headers_to_sign = props.headers
    this.header = header
    this.end_callback = done
    this.writable = true
    this.found_eoh = false
    this.buffer = { ar: [], len: 0 }
    this.hash = crypto.createHash('SHA256')
    this.line_buffer = { ar: [], len: 0 }
    this.signer = crypto.createSign('RSA-SHA256')
    this.body_found = false
    this.body_canon = props.body_canon || 'simple'
  }

  static canonicalize_body_relaxed(bufin) {
    const tmp = []
    const len = bufin.length
    let last_chunk_idx = 0
    let idx_wsp = 0
    let in_wsp = false

    for (let idx = 0; idx < len; idx++) {
      const char = bufin[idx]
      if (char === 9 || char === 32) {
        // inside WSP
        if (!in_wsp) {
          // WSP started
          in_wsp = true
          idx_wsp = idx
        }
      } else if (char === 13 || char === 10) {
        // CR?LF
        if (in_wsp) {
          // just after WSP
          tmp.push(bufin.slice(last_chunk_idx, idx_wsp))
        } else {
          // just after regular char
          tmp.push(bufin.slice(last_chunk_idx, idx))
        }
        break
      } else if (in_wsp) {
        // regular char after WSP
        in_wsp = false
        tmp.push(bufin.slice(last_chunk_idx, idx_wsp))
        tmp.push(Buffer.from(' '))
        last_chunk_idx = idx
      }
    }

    tmp.push(Buffer.from([13, 10]))

    return Buffer.concat(tmp)
  }

  write(buf) {
    /*
     ** BODY
     */

    // Merge in any partial data from last iteration
    if (this.buffer.ar.length) {
      this.buffer.ar.push(buf)
      this.buffer.len += buf.length
      const nb = Buffer.concat(this.buffer.ar, this.buffer.len)
      buf = nb
      this.buffer = { ar: [], len: 0 }
    }
    // Process input buffer into lines
    let offset = 0
    while ((offset = utils.indexOfLF(buf)) !== -1) {
      let line = buf.slice(0, offset + 1)
      if (buf.length > offset) {
        buf = buf.slice(offset + 1)
      }

      if (this.body_canon === 'relaxed') {
        line = DKIMSignStream.canonicalize_body_relaxed(line)
      }

      // Look for CRLF
      if (line.length === 2 && line[0] === 0x0d && line[1] === 0x0a) {
        // Look for end of headers marker
        if (!this.found_eoh) {
          this.found_eoh = true
        } else {
          // Store any empty lines so that we can discard
          // any trailing CRLFs at the end of the message
          this.line_buffer.ar.push(line)
          this.line_buffer.len += line.length
        }
      } else {
        if (!this.found_eoh) continue // Skip headers
        this.#hashBodyLine(line)
      }
    }
    if (buf.length) {
      // We have partial data...
      this.buffer.ar.push(buf)
      this.buffer.len += buf.length
    }
  }

  #hashBodyLine(line) {
    if (this.line_buffer.ar.length) {
      // We need to process the buffered CRLFs
      const lb = Buffer.concat(this.line_buffer.ar, this.line_buffer.len)
      this.line_buffer = { ar: [], len: 0 }
      this.hash.update(lb)
    }
    this.hash.update(line)
    this.body_found = true
  }

  // Flush any leftover partial body data, apply the empty-body rule, and
  // return the base64 body hash.
  #finalizeBodyHash() {
    // Add trailing CRLF if we have data left over
    if (this.buffer.ar.length) {
      let le = Buffer.concat(this.buffer.ar, this.buffer.len)
      if (le[le.length - 1] !== 0x0a) {
        le = Buffer.concat([le, Buffer.from('\r\n')])
      }
      if (this.body_canon === 'relaxed') {
        le = DKIMSignStream.canonicalize_body_relaxed(le)
      }
      this.hash.update(le)
      this.buffer = { ar: [], len: 0 }
    }

    if (!this.body_found) {
      this.hash.update(Buffer.from('\r\n'))
    }

    return this.hash.digest('base64')
  }

  // Feed the relaxed-canonicalized signed headers into the signer and
  // return the list of header names that were present, with one entry per
  // signed instance.
  //
  // RFC 6376 §5.4.2: when a header name occurs more than once, the signer
  // MUST sign instances bottom-to-top and list the name once per instance
  // in h=. `get_all()` returns instances in insertion (top-to-bottom)
  // order, so we iterate in reverse.
  #signHeaders() {
    const headers = []
    for (const element of this.headers_to_sign) {
      const instances = this.header.get_all(element)
      for (let i = instances.length - 1; i >= 0; i--) {
        let head = instances[i]
        if (!head) continue
        head = head.replace(/\r?\n/gm, '')
        head = head.replace(/\s+/gm, ' ')
        head = head.replace(/\s+$/gm, '')
        this.signer.update(`${element.toLowerCase()}:${head}\r\n`)
        headers.push(element)
      }
    }
    return headers
  }

  #assembleHeader(bodyhash, headers) {
    let dkim_header = `v=1; a=rsa-sha256; c=relaxed/${this.body_canon}; d=${this.domain_name}; s=${this.selector}; h=${headers.join(':')}; bh=${bodyhash}; b=`
    this.signer.update(`dkim-signature:${dkim_header}`)
    const signature = this.signer.sign(this.private_key, 'base64')
    dkim_header = `v=1; a=rsa-sha256; c=relaxed/${this.body_canon};\r\n\td=${this.domain_name}; s=${this.selector};\r\n\th=${headers.join(':')};\r\n\tbh=${bodyhash};\r\n\tb=`
    dkim_header += signature.slice(0, 74)
    for (let i = 74; i < signature.length; i += 76) {
      dkim_header += `\r\n\t${signature.slice(i, i + 76)}`
    }
    return dkim_header
  }

  end(buf) {
    this.writable = false

    const bodyhash = this.#finalizeBodyHash()
    const headers = this.#signHeaders()
    const dkim_header = this.#assembleHeader(bodyhash, headers)

    if (this.end_callback) this.end_callback(null, dkim_header)
    this.end_callback = null
  }

  destroy() {
    this.writable = false
    // Stream destroyed before the callback ran
    if (this.end_callback) {
      this.end_callback(new Error('Stream destroyed'))
    }
  }
}

module.exports = DKIMSignStream
