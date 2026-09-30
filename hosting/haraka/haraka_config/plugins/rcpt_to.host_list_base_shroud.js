'use strict';
// Base class for plugins that use config/host_list
// This is a fork of https://github.com/haraka/Haraka/blob/master/plugins/rcpt_to.host_list_base.js
// that uses a .js file for config, rather than hard-coded domains
const { Pool } = require('pg')

// Keep one bounded pool per Haraka worker instead of opening a new connection
// for every MAIL FROM and RCPT TO hook invocation.
const pool = new Pool({max: 10})
let pool_error_logger

const verified_domains_query = `SELECT domain FROM custom_domains
WHERE ownership_verified_at > (CURRENT_TIMESTAMP AT TIME ZONE 'UTC') - INTERVAL '1 day'
  AND mx_verified_at > (CURRENT_TIMESTAMP AT TIME ZONE 'UTC') - INTERVAL '1 day'
  AND spf_verified_at > (CURRENT_TIMESTAMP AT TIME ZONE 'UTC') - INTERVAL '1 day'
  AND dkim_verified_at > (CURRENT_TIMESTAMP AT TIME ZONE 'UTC') - INTERVAL '1 day'
  AND dmarc_verified_at > (CURRENT_TIMESTAMP AT TIME ZONE 'UTC') - INTERVAL '1 day'`

pool.on('error', (err) => {
    pool_error_logger?.logerror("Host list database pool error! ", Object.values(err))
})

exports.load_host_list = function (cb) {
    const plugin = this;
    pool_error_logger = plugin;

    // Connection configured via environment variables
    const domains = new Set()
    if (process.env.EMAIL_DOMAIN != null) domains.add(process.env.EMAIL_DOMAIN.toLowerCase())
    pool.query(verified_domains_query, (err, res) => {
        if (err) {
            plugin.logerror("Failed to load host list! ", Object.values(err))
        } else {
            res.rows.forEach(row => {
                domains.add(row.domain.toLowerCase())
            })
        }
        cb(domains)
    })
}

exports.hook_mail = function (next, connection, params) {
    const plugin = this;
    const txn = connection?.transaction;
    if (!txn) return;

    const email = params[0].address;
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
