---
title: /aliases
description: "API endpoints for email aliases"
---

## List email aliases

`GET /api/v1/aliases`: Lists all your email aliases.

Aliases are returned in pages of 20. You can customize pagination
using the `page_size` and `page` URL parameters, e.g. `/api/v1/aliases?page_size=10&page=3`.

### Example response

```
{
  email_aliases: [{
    "address": "deadbeef@fog.shroud.email",
    "enabled": true,
    "title": "Newsletters",
    "notes": "Used for webshop newsletters etc.",
    "forwarded": 26,
    "blocked": 33,
    "blocked_addresses": ["spammer@example.com"]
  }],
  "page_number": 1,
  "page_size": 20,
  "total_entries": 1,
  "total_pages": 1
}
```

## Create an alias

`POST /api/v1/aliases`: Create an email alias.

By sending a POST request with no arguments, this will generate a random email alias on the default, shared domain (`@fog.shroud.email`). Alternatively, you can include a POST body to create a custom alias. For example, to create `myemail@example.com`, send the following arguments:

```
{
  "local_part": "myemail",
  "domain": "example.com"
}
```

This will return a response like

```
{
  "address": "email@custom.test",
  "blocked": 0,
  "forwarded": 0,
  "title": null,
  "notes": null,
  "blocked_addresses": [],
  "enabled": true
}
```
