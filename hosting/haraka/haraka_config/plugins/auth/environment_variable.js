// Auth against a flat file

exports.register = function () {
    const plugin = this;
    plugin.inherits('auth/auth_base');
}

exports.hook_capabilities = function (next, connection) {
    const plugin = this;
    // don't allow AUTH unless private IP or encrypted
    if (!connection.remote.is_private && !connection.tls.enabled) {
        connection.logdebug(plugin,
            "Auth disabled for insecure public connection");
        return next();
    }

    const methods = ["CRAM-MD5", "PLAIN", "LOGIN"];
    connection.capabilities.push(`AUTH ${methods.join(' ')}`);
    connection.notes.allowed_auth_methods = methods;
    next();
}

exports.get_plain_passwd = function (user, cb) {
    if (user === process.env.SMTP_USERNAME) return cb(process.env.SMTP_PASSWORD)
    return cb()
}
