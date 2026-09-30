'use strict';
// Base class for plugins that use config/host_list
// This is a fork of https://github.com/haraka/Haraka/blob/master/plugins/rcpt_to.host_list_base.js
// that uses a .js file for config, rather than hard-coded domains
const { Client }= require('pg')

exports.load_host_list = function (cb) {
    const plugin = this;

    // Connection configured via environment variables
    const client = new Client()
    client.connect()
    const domains = new Set()
    if (process.env.EMAIL_DOMAIN != null) domains.add(process.env.EMAIL_DOMAIN.toLowerCase())
    client.query('SELECT domain FROM custom_domains', (err, res) => {
        if (err) {
            plugin.logerror("Failed to load host list! ", Object.values(err))
        } else {
            res.rows.forEach(row => {
                domains.add(row.domain.toLowerCase())
            })
        }
        cb(domains)
        client.end()
    })
}

exports.hook_mail = function (next, connection, params) {
    const plugin = this;
    const txn = connection?.transaction;
    if (!txn) return;

    const email = params[0].address();
    if (!email) {
        txn.results.add(plugin, {skip: 'mail_from.null', emit: true});
        return next();
    }

    const domain = params[0].host.toLowerCase();

    const anti_spoof = plugin.config.get('host_list.anti_spoof') || false;

    plugin.load_host_list((domains) => {
        if (domains.has(domain)) {
            if (anti_spoof && !connection.relaying) {
                txn.results.add(plugin, {fail: 'mail_from.anti_spoof'});
                return next(DENY, `Mail from domain '${domain}' is not allowed from your host`);
            }
            txn.results.add(plugin, {pass: 'mail_from'});
            txn.notes.local_sender = true;
            return next();
        }

        txn.results.add(plugin, {msg: 'mail_from!local'});
        return next();
    })
}
