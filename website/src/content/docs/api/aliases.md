---
title: /aliases
description: "API endpoints for email aliases"
---

## List email aliases

`GET /api/v1/aliases`: Lists all your email aliases.

Aliases are returned in pages of 20. You can customize pagination
using the `page_size` and `page` URL parameters, e.g. `/api/v1/aliases?page_size=10&page=3`.

### Search and filtering

- `search`: Case-insensitive search across the address, title, and notes, using the
  same matching rules as the dashboard. Space-separated terms match any term;
  punctuation is treated as a wildcard.
- `enabled`: Set to `true` or `false` to return only enabled or disabled aliases.

For example, `/api/v1/aliases?search=Acme&enabled=false&page_size=10` finds disabled
aliases matching "Acme". Pagination totals describe the filtered results.

### Example response

```
{
  "email_aliases": [{
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

By sending a POST request with no arguments, this will generate a random email alias on the instance's configured shared domain (`EMAIL_DOMAIN`; `fog.shroud.email` for the hosted service). Alternatively, you can include a POST body to create a custom alias. The custom domain must first be added to the authenticated user's account. For example, to create `myemail@example.com`, send the following arguments:

```
{
  "local_part": "myemail",
  "domain": "example.com",
  "title": "Acme",
  "notes": "Used for shopping receipts"
}
```

`title` and `notes` are optional strings. You can also supply them without
`local_part` and `domain` to create a labelled random alias. A custom domain must
belong to your account.

This will return a response like

```
{
  "address": "myemail@example.com",
  "blocked": 0,
  "forwarded": 0,
  "title": "Acme",
  "notes": "Used for shopping receipts",
  "blocked_addresses": [],
  "enabled": true
}
```

## Get an alias

`GET /api/v1/aliases/:address`: Fetch a single alias by its exact email address.

URL-encode the address, e.g. `/api/v1/aliases/deadbeef%40fog.shroud.email`.

Returns the alias object shown above, or `404` if the alias is not found.

## Update an alias

`PATCH /api/v1/aliases/:address`: Update an alias's label, notes, or enabled state.

```
{
  "title": "Acme shopping",
  "notes": "Receipts and order updates",
  "enabled": false
}
```

Only `title`, `notes`, and `enabled` can be updated. Omitted fields remain
unchanged. Set `title` or `notes` to `null` to clear them.

Set `enabled` to `false` to stop all forwarding, including password-reset emails,
or `true` to re-enable it.

Returns the updated alias object, `422` for invalid values, or `404` if the alias
is not found.

## Delete an alias

`DELETE /api/v1/aliases/:address`: Delete an alias from your account.

Returns `204` on success, or `422` if the alias is not found.

Prefer disabling an alias if you may need it again. Deleted aliases on shared
Shroud domains cannot be recreated; custom-domain addresses can be recreated.
