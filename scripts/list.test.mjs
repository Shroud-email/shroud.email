import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';

const entries = readFileSync(new URL('../list.txt', import.meta.url), 'utf8')
  .trim()
  .split('\n')
  .map((line) => {
    const [name, pattern] = line.split('@@=');
    return { name, regex: new RegExp(pattern) };
  });

const cases = [
  ['Substack', 'https://eotrx.substackcdn.com/open?token=abc', ['https://eotrx.substackcdn.com/image/fetch/article.png', 'https://substackcdn.com/image/fetch/article.png']],
  ['Klaviyo', 'https://ctrk.klclick2.com/abc', ['https://images.klaviyo.com/logo.png', 'https://ctrk.klclick2.com.evil.test/pixel']],
  ['beehiiv', 'https://link.mail.beehiiv.com/ls/click?x=1', ['https://cdn.beehiiv.com/logo.png', 'https://link.mail.beehiiv.com.evil.test/pixel']],
  ['Benchmark', 'https://trk42.benchurl.com/c/o?e=abc', ['https://trk42.benchurl.com/images/logo.png', 'https://trk42.benchurl.com.evil.test/c/o?e=abc']],
  ['Resend', 'https://a.resend-links.com/abc', ['https://cdn.resend.com/logo.png', 'https://a.resend-links.com.evil.test/pixel']],
  ['Omnisend', 'https://omni.soundestlink.com/abc', ['https://other.soundestlink.com/logo.png', 'https://omni.soundestlink.com.evil.test/pixel']],
];

for (const [name, tracker, ordinaryUrls] of cases) {
  test(`${name} matches its tracker URL without matching adjacent content`, () => {
    const regexes = entries.filter((entry) => entry.name === name).map((entry) => entry.regex);
    assert.ok(regexes.some((regex) => regex.test(tracker)), `missing ${tracker}`);
    for (const ordinary of ordinaryUrls) {
      assert.ok(regexes.every((regex) => !regex.test(ordinary)), `unexpected match of ${ordinary}`);
    }
  });
}
