---
title: /domains
description: "API endpoints for custom domains"
---

## List custom domains

`GET /api/v1/domains`: Lists your custom domains.

Domains are returned in pages of 20. You can customize pagination
using the `page_size` and `page` URL parameters, e.g. `/api/v1/domains?page_size=10&page=3`.

Note that this endpoint only returns domains with valid DNS records.

### Example response

```
{
  "domains": [
    {
      "domain": "example.com"
    }
  ],
  "page_number": 1,
  "page_size": 20,
  "total_entries": 1,
  "total_pages": 1
}
```
