"use strict";

const assert = require("node:assert/strict");
const {
  createHash,
  createHmac,
  generateKeyPairSync,
  verify,
} = require("node:crypto");
const dns = require("node:dns");
const { once } = require("node:events");
const fs = require("node:fs");
const net = require("node:net");
const os = require("node:os");
const path = require("node:path");
const test = require("node:test");
const { Pool } = require("pg");
const { Plugin } = require("Haraka/plugins");
const { createTransaction } = require("Haraka/transaction");

const keys = generateKeyPairSync("rsa", { modulusLength: 2048 });
const privateKey = keys.privateKey.export({ type: "pkcs1", format: "pem" });
const body = "A forwarded message.\r\nSecond line.\r\n";

function setup(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "shroud-dkim-"));
  const keydir = path.join(root, "config/dkim/base.example");
  fs.mkdirSync(keydir, { recursive: true });
  fs.writeFileSync(path.join(keydir, "private"), privateKey);
  fs.writeFileSync(path.join(keydir, "selector"), "shroudemail\n");
  fs.copyFileSync(
    path.join(__dirname, "../config/dkim.ini"),
    path.join(root, "config/dkim.ini"),
  );
  fs.symlinkSync(
    path.join(__dirname, "../plugins"),
    path.join(root, "plugins"),
  );
  const previous = {
    HARAKA: process.env.HARAKA,
    EMAIL_DOMAIN: process.env.EMAIL_DOMAIN,
    SMTP_PASSWORD: process.env.SMTP_PASSWORD,
    UNSUBSCRIBE_ATTESTATION_SECRET: process.env.UNSUBSCRIBE_ATTESTATION_SECRET,
  };
  process.env.HARAKA = root;
  process.env.EMAIL_DOMAIN = "BASE.EXAMPLE";
  process.env.SMTP_PASSWORD = "test-smtp-password";
  process.env.UNSUBSCRIBE_ATTESTATION_SECRET = "test-attestation-secret";
  t.after(() => {
    for (const [key, value] of Object.entries(previous)) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
    require("haraka-config/lib/watch").closeAll();
    fs.rmSync(root, { recursive: true, force: true });
  });

  // Load and register the folder plugin through the real Haraka loader.
  const plugin = new Plugin("dkim_shroud");
  plugin._compile();
  plugin.register();
  assert.deepEqual(Object.keys(plugin.hooks), ["data_post", "queue_outbound"]);
  assert.equal(
    plugin.cfg.sign.headers,
    "From,List-Unsubscribe,List-Unsubscribe-Post",
  );
  const shippedPlugins = fs
    .readFileSync(path.join(__dirname, "../config/plugins"), "utf8")
    .split("\n");
  assert.ok(shippedPlugins.includes("dkim_shroud"));
  assert.ok(!shippedPlugins.includes("dkim"));
  return { plugin, keydir };
}

async function message(from, envelope = "base.example") {
  const transaction = createTransaction();
  transaction.mail_from = { host: envelope };
  const results = [];
  transaction.results = { add: (_plugin, result) => results.push(result) };
  for (const line of `From: ${from}\r\nTo: recipient@elsewhere.example\r\nSubject: DKIM test\r\n\r\n${body}`.split(
    /(?<=\n)/,
  )) {
    transaction.add_data(Buffer.from(line));
  }
  await new Promise((resolve) => transaction.end_data(resolve));
  const logs = [];
  const log = (_plugin, text) => logs.push(text);
  return {
    transaction,
    results,
    logs,
    logdebug: log,
    loginfo: log,
    lognotice: log,
    logerror: log,
    logprotocol: log,
    auth_results: () => {},
  };
}

function sign(plugin, connection) {
  return new Promise((resolve) =>
    plugin.hook_pre_send_trans_email((...args) => resolve(args), connection),
  );
}

function checkSignature(connection, from, domain) {
  const signature = connection.transaction.header.get("DKIM-Signature");
  assert.match(
    signature,
    new RegExp(`d=${domain.replaceAll(".", "\\.")}; s=shroudemail;`),
  );
  assert.match(signature, /c=relaxed\/simple;/);
  assert.match(signature, /h=from;/);
  const expectedBodyHash = createHash("sha256").update(body).digest("base64");
  assert.ok(signature.includes(`bh=${expectedBodyHash};`));
  // Independently reconstruct RFC 6376 relaxed headers and verify with the public key.
  const unfolded = signature.trim().replace(/\r?\n[ \t]+/g, " ");
  const encoded = unfolded.match(/\bb=([\s\S]*)$/)[1].replace(/\s/g, "");
  const unsigned = unfolded.replace(/\bb=[\s\S]*$/, "b=");
  assert.ok(
    verify(
      "RSA-SHA256",
      Buffer.from(`from:${from}\r\ndkim-signature:${unsigned}`),
      keys.publicKey,
      Buffer.from(encoded, "base64"),
    ),
  );
  assert.equal(connection.transaction.notes.dkim_signed, true);
}

test("base-domain signing retains upstream behavior and needs no database", async (t) => {
  const { plugin } = setup(t);
  t.mock.method(Pool.prototype, "query", async () => {
    throw new Error("must not query");
  });
  const connection = await message("sender@base.example");
  assert.deepEqual(await sign(plugin, connection), []);
  checkSignature(connection, "sender@base.example", "base.example");
});

function inbound(plugin, connection) {
  return new Promise((resolve) =>
    plugin.dkim_verify((...args) => resolve(args), connection),
  );
}

function unsubscribeHeaders(connection, post = true) {
  const txn = connection.transaction;
  txn.add_header(
    "List-Unsubscribe",
    "<https://sender.example/unsubscribe>,\r\n\t<mailto:leave@sender.example> ",
  );
  if (post)
    txn.add_header("List-Unsubscribe-Post", "List-Unsubscribe=One-Click ");
  txn.add_header("X-Shroud-Unsubscribe", "spoofed");
  txn.add_header("X-Shroud-Unsubscribe", "also-spoofed");
  txn.add_header(
    "Authentication-Results",
    "sender.example; dkim=pass header.d=base.example",
  );
}

for (const header of ["constructor", "__proto__"]) {
  for (const present of [false, true]) {
    test(`real verification handles ${present ? "oversigned" : "absent"} ${header} headers without trusting spoofed attestations`, async (t) => {
      const { plugin } = setup(t);
      t.mock.method(dns.promises, "resolveTxt", async () => [
        [
          `v=DKIM1; p=${keys.publicKey.export({ type: "spki", format: "der" }).toString("base64")}`,
        ],
      ]);
      const connection = await message("sender@base.example");
      unsubscribeHeaders(connection);
      const txn = connection.transaction;
      if (present) {
        // Haraka refuses these names when adding headers. Inject the actual
        // wire field at the stream boundary to exercise the verifier's index.
        const stream = txn.message_stream;
        const pipe = stream.pipe.bind(stream);
        t.mock.method(stream, "pipe", (destination, options) => {
          destination.write(Buffer.from(`${header}: actual input field\r\n`));
          return pipe(destination, options);
        });
      }
      const signedHeaders = present
        ? `from:${header}:${header}`
        : `from:${header}`;
      // A matching body hash reaches header canonicalization. The deliberately
      // invalid signature then fails normally, rather than throwing on .pop().
      txn.add_header(
        "DKIM-Signature",
        `v=1; a=rsa-sha256; d=base.example; s=shroudemail; h=${signedHeaders}; bh=${createHash("sha256").update(body).digest("base64")}; b=AQ==`,
      );
      assert.deepEqual(await inbound(plugin, connection), []);
      assert.equal(txn.notes.dkim_results.length, 1);
      assert.equal(txn.notes.dkim_results[0].result, "fail");
      assert.equal(txn.notes.dkim_results[0].error, undefined);
      assert.deepEqual(
        txn.notes.dkim_results[0].signed_headers,
        signedHeaders.split(":"),
      );
      assert.equal(txn.header.get_all("X-Shroud-Unsubscribe").length, 0);
      assert.equal(dns.promises.resolveTxt.mock.callCount(), 1);
    });
  }
}

test("real verification preserves original signed bytes and emits the HMAC wire contract", async (t) => {
  const { plugin } = setup(t);
  t.mock.method(dns.promises, "resolveTxt", async () => [
    [
      `v=DKIM1; p=${keys.publicKey.export({ type: "spki", format: "der" }).toString("base64")}`,
    ],
  ]);
  const connection = await message("sender@base.example");
  unsubscribeHeaders(connection);
  // Include the spoofed header in the original signature: removing it before
  // verification would invalidate this otherwise passing signature.
  plugin.cfg.headers_to_sign.push("x-shroud-unsubscribe");
  await sign(plugin, connection);
  await inbound(plugin, connection);
  const txn = connection.transaction;
  assert.equal(txn.notes.dkim_results[0].result, "pass");
  assert.ok(
    txn.notes.dkim_results[0].signed_headers.includes("list-unsubscribe-post"),
  );
  const attestations = txn.header.get_all("X-Shroud-Unsubscribe");
  assert.equal(attestations.length, 1);
  const wire = attestations[0].trim();
  assert.match(wire, /^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/);
  const [payload, mac] = wire.split(".");
  const decoded = JSON.parse(
    Buffer.from(payload, "base64url").toString("utf8"),
  );
  assert.deepEqual(decoded, {
    unsubscribe:
      "<https://sender.example/unsubscribe>, <mailto:leave@sender.example>",
    post: "List-Unsubscribe=One-Click",
    timestamp: decoded.timestamp,
  });
  assert.ok(Math.abs(decoded.timestamp - Math.floor(Date.now() / 1000)) <= 2);
  assert.equal(
    mac,
    createHmac("sha256", "test-attestation-secret")
      .update(`shroud-unsubscribe:${payload}`)
      .digest("base64url"),
  );

  // Model the app replacing original headers with generated one-click URLs.
  txn.remove_header("DKIM-Signature");
  txn.remove_header("List-Unsubscribe");
  txn.remove_header("List-Unsubscribe-Post");
  txn.add_header(
    "List-Unsubscribe",
    "<https://shroud.example/unsubscribe/token>",
  );
  txn.add_header("List-Unsubscribe-Post", "List-Unsubscribe=One-Click");
  txn.notes.dkim_signed = false;
  await sign(plugin, connection);
  const final = await plugin.run_verify_stream(txn);
  assert.equal(final[0].result, "pass");
  assert.ok(final[0].signed_headers.includes("list-unsubscribe"));
  assert.ok(final[0].signed_headers.includes("list-unsubscribe-post"));
});

test("attestation fails closed on spoofing, failures, coverage, alignment and duplicates", async (t) => {
  const { plugin } = setup(t);
  const covered = ["from", "list-unsubscribe", "list-unsubscribe-post"];
  const pass = {
    result: "pass",
    domain: "base.example",
    signed_headers: covered,
  };
  for (const scenario of [
    "none",
    "error",
    "fail",
    "unaligned",
    "missing-unsubscribe",
    "missing-post",
    "split",
    "duplicate-unsubscribe",
    "duplicate-post",
    "duplicate-from",
    "bad-marker",
    "no-secret",
    "valid",
    "no-post",
  ]) {
    const connection = await message("sender@base.example");
    unsubscribeHeaders(connection, scenario !== "no-post");
    const txn = connection.transaction;
    let results = [{ ...pass }];
    if (scenario === "none") results = [];
    if (scenario === "fail") results[0].result = "fail";
    if (scenario === "unaligned") results[0].domain = "sub.base.example";
    if (scenario.startsWith("missing-"))
      results[0].signed_headers = covered.filter(
        (h) =>
          h !==
          (scenario === "missing-post"
            ? "list-unsubscribe-post"
            : "list-unsubscribe"),
      );
    if (scenario === "split")
      results = [
        { ...pass, signed_headers: ["from", "list-unsubscribe"] },
        { ...pass, signed_headers: ["from", "list-unsubscribe-post"] },
      ];
    if (scenario.startsWith("duplicate-"))
      txn.add_header(
        {
          "duplicate-unsubscribe": "List-Unsubscribe",
          "duplicate-post": "List-Unsubscribe-Post",
          "duplicate-from": "From",
        }[scenario],
        "duplicate",
      );
    if (scenario === "bad-marker") {
      txn.remove_header("List-Unsubscribe-Post");
      txn.add_header("List-Unsubscribe-Post", "list-unsubscribe=one-click");
    }
    process.env.UNSUBSCRIBE_ATTESTATION_SECRET =
      scenario === "no-secret" ? "" : "test-attestation-secret";
    t.mock.method(plugin, "run_verify_stream", async () => {
      assert.equal(txn.header.get_all("X-Shroud-Unsubscribe").length, 2);
      if (scenario === "error") throw new Error("verifier failed");
      return results;
    });
    await inbound(plugin, connection);
    const attestations = txn.header.get_all("X-Shroud-Unsubscribe");
    assert.equal(
      attestations.length,
      ["valid", "no-post"].includes(scenario) ? 1 : 0,
      scenario,
    );
    if (scenario === "no-post")
      assert.equal(
        JSON.parse(
          Buffer.from(attestations[0].trim().split(".")[0], "base64url"),
        ).post,
        null,
      );
  }
});

test("attestation bounds raw List-Unsubscribe values by UTF-8 bytes", async (t) => {
  const { plugin } = setup(t);
  const prefix = "<https://sender.example/";
  for (const [name, padding, bytes, accepted] of [
    ["exact ASCII limit", "a".repeat(4071), 4096, true],
    ["over ASCII limit", "a".repeat(4072), 4097, false],
    ["exact UTF-8 limit", "é".repeat(2035) + "a", 4096, true],
    ["over UTF-8 limit", "é".repeat(2036), 4097, false],
    ["raw limit before unfolding", "a".repeat(4069) + "\r\n\t", 4097, false],
  ]) {
    const value = `${prefix}${padding}>`;
    assert.equal(Buffer.byteLength(value, "utf8"), bytes, name);
    const connection = await message("sender@base.example");
    unsubscribeHeaders(connection);
    const txn = connection.transaction;
    const getAll = txn.header.get_all.bind(txn.header);
    // Supply raw header values: Haraka's add_header encodes non-ASCII text.
    t.mock.method(txn.header, "get_all", (header) =>
      header === "List-Unsubscribe" ? [value] : getAll(header),
    );
    t.mock.method(plugin, "run_verify_stream", async () => {
      assert.deepEqual(
        txn.header
          .get_all("X-Shroud-Unsubscribe")
          .map((v) => v.trim())
          .sort(),
        ["also-spoofed", "spoofed"],
      );
      return [
        {
          result: "pass",
          domain: "base.example",
          signed_headers: ["from", "list-unsubscribe", "list-unsubscribe-post"],
        },
      ];
    });
    await inbound(plugin, connection);
    const attestations = txn.header.get_all("X-Shroud-Unsubscribe");
    assert.equal(attestations.length, accepted ? 1 : 0, name);
    if (accepted) {
      const payload = attestations[0].trim().split(".")[0];
      assert.equal(
        JSON.parse(Buffer.from(payload, "base64url")).unsubscribe,
        value,
        name,
      );
    }
  }
});

test("concurrent custom domains use the shared key but retain distinct From domains", async (t) => {
  const { plugin } = setup(t);
  const queried = [];
  t.mock.method(Pool.prototype, "query", async function (sql, params) {
    assert.equal(this.options.connectionTimeoutMillis, 5000);
    assert.equal(this.options.query_timeout, 5000);
    assert.match(sql, /lower\(domain\) = \$1/);
    assert.match(sql, /ownership_verified_at > .* - INTERVAL '24 hours'/);
    queried.push(params[0]);
    return { rows: [{ domain: params[0] }] };
  });
  const froms = [
    "external_at_sender.example_alias@First.example",
    "alias@second.example",
  ];
  const connections = await Promise.all(froms.map((from) => message(from)));
  assert.deepEqual(
    await Promise.all(
      connections.map((connection) => sign(plugin, connection)),
    ),
    [[], []],
  );
  checkSignature(connections[0], froms[0], "first.example");
  checkSignature(connections[1], froms[1], "second.example");
  assert.deepEqual(queried.sort(), ["first.example", "second.example"]);
});

test("unknown or expired domains continue unsigned without default-key fallback", async (t) => {
  const { plugin } = setup(t);
  plugin.cfg.sign.domain = "base.example";
  plugin.cfg.sign.selector = "shroudemail";
  plugin.private_key = privateKey;
  t.mock.method(Pool.prototype, "query", async () => ({ rows: [] }));
  const connection = await message("sender@unverified.example");
  assert.deepEqual(await sign(plugin, connection), []);
  assert.equal(connection.transaction.header.get("DKIM-Signature"), "");
  assert.ok(
    connection.logs.some((log) => log.includes("unverified custom domain")),
  );
});

test("database failure is logged and continues unsigned", async (t) => {
  const { plugin } = setup(t);
  t.mock.method(Pool.prototype, "query", async () => {
    throw new Error("database unavailable");
  });
  const connection = await message("alias@customer.example");
  assert.deepEqual(await sign(plugin, connection), []);
  assert.equal(connection.transaction.header.get("DKIM-Signature"), "");
  assert.ok(connection.logs.includes("database unavailable"));
});

test(
  "a stalled PostgreSQL connection times out and continues unsigned",
  { timeout: 15000 },
  async (t) => {
    const { plugin } = setup(t);
    const sockets = new Set();
    // Accept the real pg client's TCP connection but never answer its startup packet.
    const server = net.createServer((socket) => {
      sockets.add(socket);
    });
    server.listen(0, "127.0.0.1");
    await once(server, "listening");
    const previous = { PGHOST: process.env.PGHOST, PGPORT: process.env.PGPORT };
    process.env.PGHOST = "127.0.0.1";
    process.env.PGPORT = String(server.address().port);
    t.after(async () => {
      for (const [key, value] of Object.entries(previous)) {
        if (value === undefined) delete process.env[key];
        else process.env[key] = value;
      }
      for (const socket of sockets) socket.destroy();
      await new Promise((resolve) => server.close(resolve));
    });
    const connection = await message("alias@customer.example");
    assert.deepEqual(await sign(plugin, connection), []);
    assert.equal(connection.transaction.header.get("DKIM-Signature"), "");
    assert.ok(connection.logs.some((log) => /timeout|timed out/i.test(log)));
  },
);

test("missing installation key or selector continues unsigned", async (t) => {
  const { plugin } = setup(t);
  t.mock.method(Pool.prototype, "query", async () => ({
    rows: [{ domain: "customer.example" }],
  }));
  for (const missing of ["private", "selector"]) {
    t.mock.method(plugin, "load_key", (file) => {
      if (file.endsWith(`/${missing}`)) return "";
      return file.endsWith("/private") ? privateKey : "shroudemail";
    });
    const connection = await message("alias@customer.example");
    assert.deepEqual(await sign(plugin, connection), []);
    assert.equal(connection.transaction.header.get("DKIM-Signature"), "");
    assert.ok(connection.logs.some((log) => log.startsWith("skipped: no ")));
  }
});

test("upstream signing-error callback and already-signed behavior are unchanged", async (t) => {
  const { plugin } = setup(t);
  t.mock.method(Pool.prototype, "query", async () => ({
    rows: [{ domain: "customer.example" }],
  }));
  const error = new Error("signing stream failed");
  t.mock.method(plugin, "run_sign_stream", async () => {
    throw error;
  });
  const connection = await message("alias@customer.example");
  assert.deepEqual(await sign(plugin, connection), [error]);
  assert.ok(connection.results.some((result) => result.err === error.message));
  connection.transaction.notes.dkim_signed = true;
  assert.deepEqual(await sign(plugin, connection), []);
  assert.equal(plugin.run_sign_stream.mock.callCount(), 1);
});
