# Admin mailserver health diagnostics

## Goal and boundary

Provide an on-demand, admin-only page that diagnoses the configured `EMAIL_DOMAIN` mail setup without sending messages, modifying DNS, or accepting user-supplied targets. Show independently actionable results with `pass`, `fail`, or `unknown` status, observed values, and short explanations. These are diagnostics from the running web container, **not** a guarantee of external reachability or end-to-end delivery.

## Deployment model

In the hosting repository, Haraka listens publicly on port 25 and forwards accepted mail to the Phoenix SMTP listener at port 1587. The app submits outbound mail to its configured relay (`haraka` in the default Compose deployment). Caddy obtains a certificate for `EMAIL_DOMAIN`; a daily cron job copies it to Haraka for STARTTLS. Haraka signs outgoing messages with selector `shroudemail`. The app's HTTPS certificate is not the SMTP certificate being checked.

## Checks

- **DNS:** Resolve the configured alias domain's MX targets and each target's A/AAAA addresses; report absence, DNS failures, and the actual records. Check for a syntactically valid SPF TXT policy on the alias domain, a `shroudemail._domainkey` DKIM TXT public key, and a syntactically valid `_dmarc` TXT policy. Do not claim that presence of these records proves message authentication or that SPF authorizes every actual sending IP; report such limitations. DNS errors are `unknown`, whereas authoritative missing/invalid records are `fail`.
- **Public SMTP endpoint:** For each published MX target, attempt a short TCP connection to port 25, read the SMTP greeting, issue EHLO, require advertised STARTTLS, upgrade, and verify the certificate chain, hostname (the MX target), and validity dates. Keep per-target results, including failures; never silently pass if one MX target is broken. This probe runs from the app container, so a successful connection does not prove an external sender can reach port 25. Do not probe arbitrary ports 465/587: this deployment does not expose them publicly.
- **Private pipeline:** Check that the local Phoenix listener accepts a connection on its configured internal SMTP port and presents a greeting. Probe the configured outbound relay host/port from the existing mailer configuration, reading its greeting and EHLO/STARTTLS availability as appropriate to its configured TLS mode. Do not send mail or reveal relay credentials. SMTP authentication and downstream delivery remain unverified without sending a message.
- **Boundaries:** A DNS lookup, TCP connection, EHLO, and TLS negotiation are read-only. Do not issue `MAIL FROM`, `RCPT TO`, `DATA`, or a credential-bearing AUTH command. Do not claim to test public firewall reachability, reverse DNS of the real outbound IP, actual DKIM signatures, delivery, or acceptance of a particular recipient. If a check cannot run in a development environment, show `unknown` rather than a misleading `pass`.

## Page and execution

Add a LiveView under the existing admin-only browser pipeline and `AdminUserLiveAuth` session, linked in both desktop and mobile admin navigation. On opening the page and on an explicit Refresh action, run checks asynchronously so network timeouts do not block the LiveView process. Display a run timestamp, per-check status and detail, and an in-progress state; bound every DNS, socket, and TLS operation with short timeouts and close sockets on all paths. No persistent tables, periodic workers, external APIs, configuration knobs, or changes to the hosting repository are needed.

Keep the checker separate from presentation, using the application's configured domain, SMTP listener port, and Swoosh SMTP relay settings. All targets come from server configuration or DNS MX records for the server-configured domain, never from request parameters; limit the number of probed MX targets and total runtime to avoid turning admin access into an unbounded network probe. Prefer existing Erlang DNS and socket/SSL APIs and the repository's test injection conventions over new dependencies.

## Verification

Test DNS interpretation and multi-MX aggregation with asymmetric records, missing/invalid records, and resolver failures. Test SMTP greeting/EHLO/STARTTLS and certificate failure boundaries with controlled local endpoints or injected clients; ensure a greeting without STARTTLS cannot pass. Test that only admins can load and refresh the LiveView, that no user input controls a target, and that results render independently when another probe fails. Run focused ExUnit checks, format/compile checks, and inspect the rendered default, running, and failure states in the dev UI where the environment supports it.
