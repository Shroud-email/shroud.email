---
title: Authentication
description: Authenticate API requests and protect your account credentials.
---

The API uses bearer tokens to authorize access to your Shroud.email account. Obtain a token using the [token-creation operation](/api/operations/createtoken/) in the API reference, then include it in the `Authorization` header when calling authenticated operations:

```http
Authorization: Bearer YOUR_API_TOKEN
```

Token creation uses your account credentials. If you have two-factor authentication enabled, you also need a current TOTP code. See the generated reference for the exact request format and responses.

:::caution[Keep tokens secret]
A token grants access to your account. Treat it like a password: do not commit it to source control, include it in URLs, or publish it in logs or screenshots.
:::

Store credentials and tokens in your application's secret store or environment configuration. Keep authenticated requests on a trusted server rather than embedding a token in publicly shipped browser code. Use HTTPS, including on self-hosted instances.

For the hosted service, authenticate against `https://app.shroud.email`, not this documentation site. For a self-hosted instance, replace that host with your own application domain. A token belongs to the instance that issued it.
