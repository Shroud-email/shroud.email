"use strict";

const { createPrivateKey, X509Certificate } = require("node:crypto");
const tls = require("node:tls");

exports.register = function () {
  const tlsSocket = this.haraka_require("tls_socket");
  const bundlePath = "certs/tls.pem";
  let lastBundle = tlsSocket.config.get(bundlePath, "binary");
  this._interval = setInterval(() => {
    try {
      // Haraka's watcher updates the cache, but other readers can replace its
      // single callback slot. Poll the cached bytes independently in each worker.
      const bundle = tlsSocket.config.get(bundlePath, "binary");
      if (!bundle || (lastBundle && bundle.equals(lastBundle))) return;
      // Remember rejected bytes too, so invalid input is logged only once.
      lastBundle = bundle;
      // Reject incomplete or mismatched pairs without changing the active TLS state.
      if (
        !new X509Certificate(bundle).checkPrivateKey(createPrivateKey(bundle))
      ) {
        throw new Error("Certificate and private key do not match");
      }
      tls.createSecureContext({ key: bundle, cert: bundle });
      tlsSocket.load_tls_ini();
      this.loginfo("Reloaded SMTP TLS certificate bundle");
    } catch (err) {
      this.logerror(
        `Cannot reload SMTP TLS certificate bundle: ${err.message}`,
      );
    }
  }, 1000);
  this._interval.unref();
};

exports.shutdown = function () {
  clearInterval(this._interval);
};
