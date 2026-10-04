# OAuth clients

Shroud.email uses Authorization Code with PKCE S256 for public clients. Clients
do not have a secret. Browser login, passkeys, and two-factor authentication stay
on the Shroud website. Every connection requires a confirmed account and consent.

## Resources and permissions

The issuer is the configured Phoenix endpoint URL. On hosted Shroud.email this
is `https://app.shroud.email`. Self-hosted clients must use their instance's URL.

| Resource | Available scopes | Registration |
| --- | --- | --- |
| `https://app.shroud.email/api/v1` | `profile:read`, `aliases:read`, `aliases:create`, `aliases:edit`, `aliases:delete`, `domains:read` | Administrator-provisioned public clients |
| `https://app.shroud.email/mcp` | `aliases:read`, `aliases:create`, `aliases:edit`, `domains:read` | Administrator-provisioned or dynamic public clients |

Mutation scopes also require `aliases:read` at consent. Tokens for one resource
cannot access the other. MCP authorization and access require the
`chatgpt_integration` feature flag; REST access and Connected apps do not.

REST endpoint scopes:

| Operation | Scope |
| --- | --- |
| GET `/api/v1/me` (account ID and email address) | `profile:read` |
| GET `/api/v1/aliases` and `/api/v1/aliases/:address` | `aliases:read` |
| POST `/api/v1/aliases` | `aliases:create` |
| PATCH `/api/v1/aliases/:address` | `aliases:edit` |
| DELETE `/api/v1/aliases/:address` | `aliases:delete` |
| GET `/api/v1/domains` | `domains:read` |

Use `Authorization: Bearer <access_token>`. Missing or invalid API credentials
return 401 with a discovery challenge. Insufficient scope returns 403 with the
required scope. Account session tokens from `/api/v1/token` also work, with full
account permissions. Browser cookies are not API credentials. This server does
not provide OpenID Connect, ID tokens, or Enterprise workspace domain restrictions.

## Provision mobile and extension clients

Choose a UUID once for each client and keep it stable. Provision each against
the intended database. This command writes client registration data; run it in
production only as an approved deployment operation.

From the `shroud.email/` directory:

```sh
mix oauth.client --id "$MOBILE_CLIENT_ID" --name 'Shroud.email mobile' \
  --resource api --redirect-uri 'https://app.shroud.email/oauth/callback'
```

Repeat for each browser extension, using its actual browser-provided HTTPS
callback. For Chrome, obtain the URL with
`chrome.identity.getRedirectURL('oauth/callback')`. For Firefox, use
`browser.identity.getRedirectURL('oauth/callback')`. Register the exact returned
URL, not a wildcard or `chrome-extension://` / `moz-extension://` URL. Development
and store builds can have different extension IDs; use separate registrations
or repeat `--redirect-uri` for approved callbacks.

In a running release, provision through the release RPC command instead of Mix:

```sh
bin/shroud rpc 'Shroud.Mcp.Clients.provision!("<client-uuid>", "Shroud.email mobile", "/api/v1", ["https://app.shroud.email/oauth/callback"])'
```

Re-provisioning the same registered ID updates its name and callbacks. Dynamic
registrations cannot be overwritten. Only HTTPS and loopback HTTP callbacks
are allowed. Clients cannot make themselves administrator-provisioned through
`/oauth/register`. Removing a client row disables its connections immediately.

## Client flow

1. Generate fresh cryptographically random `state` and a PKCE verifier.
2. Compute the S256 challenge and open `/oauth/authorize` in a browser with
   `client_id`, `redirect_uri`, `response_type=code`, `scope`, `resource`,
   `state`, `code_challenge`, and `code_challenge_method=S256`.
3. Validate the callback's exact origin/path, `state`, and `iss`. Reject duplicate
   credential parameters. Handle denial without exchanging a code.
4. POST form data to `/oauth/token`: `grant_type=authorization_code`, `code`,
   `client_id`, the original `redirect_uri`, `code_verifier`, and `resource`.
5. Store credentials securely. Use the access token for API requests.
6. Refresh with `grant_type=refresh_token`, `refresh_token`, `client_id`, and the
   same `resource`. Persist the new refresh token before another refresh.
7. On logout, POST `token` and `client_id` to `/oauth/revoke` and clear credentials.

Access tokens last one hour. Codes last five minutes. Connections have a fixed
90-day lifetime; refreshing does not extend that lifetime. Refreshes rotate
credentials, and replay revokes the entire connection. Serialize refreshes in
each client. Users can revoke connections immediately in Settings → Security →
Connected apps. Do not log token bodies or place access/refresh tokens in URLs.

OAuth endpoints and REST endpoints support cookieless cross-origin requests.
Extensions should exchange and store credentials in their background context,
not a content script. Limit manifest host permissions to the Shroud instance.
Public client IDs and display names do not cryptographically authenticate an
installed client; PKCE protects each authorization transaction.

## Mobile HTTPS links

The Expo application uses bundle/package ID `email.shroud.app` and associated
domain `app.shroud.email`. Claimed paths are `/`, `/explore`, and
`/oauth/callback`; add supported native routes to both the app and association
documents as screens become available. Login and web settings stay in the browser.

The server defaults to Apple team ID `U9MQ2D642F`, producing association app ID
`U9MQ2D642F.email.shroud.app`. Configure these runtime values as needed:

- `MOBILE_APPLE_TEAM_ID`: override the 10-character Apple team ID. Verify that
  the application's signing identifier prefix matches it.
- `MOBILE_ANDROID_SHA256_CERT_FINGERPRINTS`: comma-separated, colon-separated
  SHA-256 signing certificate fingerprints. For Play Store builds use the
  **Play App Signing certificate**, not the upload certificate.

The server serves `/.well-known/apple-app-site-association` and
`/.well-known/assetlinks.json` directly as JSON. Unconfigured platforms return
an uncached 404, not a document with dummy signing identities. Ensure proxies
serve these paths on `app.shroud.email` without redirects or authentication.

Set `EXPO_PUBLIC_OAUTH_CLIENT_ID` to the provisioned mobile UUID before building.
The native client uses Expo AuthSession PKCE, native SecureStore, and HTTPS auth
sessions. HTTPS auth sessions require iOS 17.4+; older iOS and web sign-in are
explicitly unsupported. No fallback weakens callback validation.

Build and sign the native apps with Associated Domains enabled in Apple's
provisioning profile. Test cold-start and foreground callbacks on real iOS and
Android devices. Expo Go, a browser preview, and config checks do not verify OS
domain associations. If no app handles the callback, the web response explains
that a native app is required and does not expose credentials in its body.

## Published ChatGPT MCP integration

ChatGPT can use dynamic registration at `/oauth/register`, or a predefined public
MCP client. Keep registration IDs stable across releases. Copy the exact callback
from OpenAI's management page; do not infer it from a development connection.
For predefined clients, provision with `--resource mcp` and repeat
`--redirect-uri` for each production and review callback OpenAI supplies.

The server advertises `token_endpoint_auth_methods_supported: ["none"]`, S256,
and issuer identification. Configure OpenAI's public-client PKCE flow. Dynamic
registration remains available; Client ID Metadata Documents (CIMD) and signed
client assertions are not advertised or implemented. Enable `chatgpt_integration`
for users and reviewers who need MCP access before publication. Mobile tokens
must never be reused for ChatGPT.

See [OpenAI's authentication guide](https://developers.openai.com/plugins/build/auth)
for current publication and callback requirements. App packaging, review,
production registration, and publication are separate deployment operations.
