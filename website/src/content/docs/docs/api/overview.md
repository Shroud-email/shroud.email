---
title: API overview
description: Build integrations with your Shroud.email account.
---

The Shroud.email API lets you manage email aliases and discover the custom domains available to your account. Use it to integrate email privacy into your own tools and workflows.

For the hosted service, send requests to `https://app.shroud.email`. If you self-host, use your instance's web application domain instead. This documentation site does not serve API requests.

## Getting started

1. Read the [authentication guide](/docs/api/authentication/) to learn how to use an account token safely.
2. Use the API reference in the sidebar for each operation's parameters, request bodies, responses, and examples.
3. Start with a test alias before using an integration with addresses you depend on.

The reference is generated from the application's [OpenAPI specification](/docs/openapi.json). You can also use that specification with OpenAPI-compatible client generators and development tools. It is the source of truth for endpoint details; these guides focus on how to get started.

## Getting help

For integration questions, ask in [GitHub Discussions](https://github.com/Shroud-email/shroud.email/discussions/categories/q-a). Report API bugs in the [issue tracker](https://github.com/Shroud-email/shroud.email/issues). Remove account credentials, bearer tokens, and private email addresses before sharing request logs.
