"use strict";

const assert = require("node:assert/strict");
const path = require("node:path");
const test = require("node:test");
const { Plugin } = require("Haraka/plugins");
const { OK } = require("haraka-constants");

test("reply recipients are local without granting reply-domain senders relay privileges", (t) => {
  const previous = {
    HARAKA: process.env.HARAKA,
    EMAIL_DOMAIN: process.env.EMAIL_DOMAIN,
  };
  process.env.HARAKA = path.resolve(__dirname, "..");
  process.env.EMAIL_DOMAIN = "BASE.EXAMPLE";
  t.after(() => {
    for (const [key, value] of Object.entries(previous)) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
    require("haraka-config/lib/watch").closeAll();
  });
  const plugin = new Plugin("rcpt_to.in_host_list_shroud");
  plugin._compile();
  plugin.register();
  plugin.load_host_list = (callback) => callback(new Set(["base.example"]));
  const connection = {
    transaction: { notes: {}, results: { add() {} } },
    relaying: true,
    logdebug() {},
  };
  const rcpt = (host) => {
    let result = "not called";
    plugin.hook_rcpt(
      (code) => {
        result = code;
      },
      connection,
      [{ host }],
    );
    return result;
  };
  assert.equal(rcpt("token.second.42.R1.REPLY.BASE.EXAMPLE"), OK);
  assert.equal(rcpt("disabled.r1.reply.base.example"), OK);
  assert.equal(rcpt("token.42.r1.reply.base.example.evil.example"), undefined);
  assert.equal(rcpt("replybase.example"), undefined);
  plugin.hook_mail(() => {}, connection, [
    {
      address: "x@token.42.r1.reply.base.example",
      host: "token.42.r1.reply.base.example",
    },
  ]);
  assert.equal(connection.transaction.notes.local_sender, undefined);
  assert.equal(rcpt("elsewhere.example"), undefined);
  assert.equal(rcpt("base.example"), OK);
});
