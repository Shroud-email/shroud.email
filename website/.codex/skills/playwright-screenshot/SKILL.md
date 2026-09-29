---
name: playwright-screenshot
description: Take screenshots of web pages using Playwright (via npx), including multiple viewport widths for responsive testing across desktop, tablet, and mobile. Use when a user asks to capture screenshots of a URL or verify layout at different screen sizes.
---

# Playwright Screenshot

## Quick start

Run the bundled script to capture a URL at multiple widths:

```bash
scripts/take_screenshots.sh "https://example.com" ./screenshots "1440,1200,1024,768,375" 900
```

If Playwright browsers are missing, install once:

```bash
npx playwright install
```

## Usage notes

- Provide a comma-separated width list; the script outputs `WIDTHw.png` files.
- Use a taller height if the page needs more vertical space before `--full-page` captures.
- Prefer `file://` URLs for local HTML when you want deterministic, offline screenshots.

## Script reference

- `scripts/take_screenshots.sh <url> [output_dir] [widths_csv] [height]`
- Defaults: `output_dir=./screenshots`, `widths_csv=1440,1200,1024,768,375`, `height=900`.
