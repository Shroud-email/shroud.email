'use strict';
// This is a fork of https://github.com/haraka/Haraka/blob/master/plugins/rcpt_to.in_host_list.js

// Previous versions of this plugin (Haraka <= 2.4.0) did not account for
// relaying users. This plugin now permits relaying clients to send if
// the message is destined to or originating from a local domain.
//
// The mail hook always checks the MAIL FROM address and when detected, sets
// connection.transaction.notes.local_sender=true. During RCPT TO, if relaying
// is enabled and the sending domain is local, the receipt is OK.

exports.register = function () {
    const plugin = this;
    plugin.inherits('rcpt_to.host_list_base_shroud');
}

exports.hook_rcpt = function (next, connection, params) {
    const plugin = this;

    const txn = connection?.transaction;
    if (!txn) return;

    const rcpt = params[0];

    // Check for RCPT TO without an @ first - ignore those here
    if (!rcpt.host) {
        txn.results.add(plugin, {fail: 'rcpt!domain'});
        return next();
    }

    plugin.load_host_list((domains) => {
        connection.logdebug(plugin, `Checking if ${rcpt} host is in host_list`);

        const domain = rcpt.host.toLowerCase();

        if (domains.has(domain)) {
            txn.results.add(plugin, {pass: 'rcpt_to'});
            return next(OK);
        }

        // in this case, a client with relaying privileges is sending FROM a local
        // domain. For them, any RCPT address is accepted.
        if (connection.relaying && txn.notes.local_sender) {
            txn.results.add(plugin, {pass: 'relaying local_sender'});
            return next(OK);
        }

        // the MAIL FROM domain is not local and neither is the RCPT TO
        // Another RCPT plugin may yet vouch for this recipient.
        txn.results.add(plugin, {msg: 'rcpt!local'});
        return next();
    });
}
