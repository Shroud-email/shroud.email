import { describe, expect, it } from 'vitest';
import { normalizeInstance } from '../../shared/instance';

describe('instance selection', () => {
  it('accepts canonical HTTPS origins and loopback development origins', () => {
    expect(normalizeInstance(' https://mail.example:8443/ ')).toBe('https://mail.example:8443');
    expect(normalizeInstance('https://MAIL.example/')).toBe('https://mail.example');
    expect(normalizeInstance('http://127.0.0.1:4000')).toBe('http://127.0.0.1:4000');
    expect(normalizeInstance('http://localhost:4000/')).toBe('http://localhost:4000');
    expect(normalizeInstance('http://[::1]:4000')).toBe('http://[::1]:4000');
  });

  it.each([
    'http://mail.example', 'https://u:p@mail.example', 'https://mail.example/path',
    'https://mail.example?x=1', 'https://mail.example#x', 'https://mail.example?',
    'https://mail.example#', 'http://localhost.evil.example', 'ftp://mail.example',
    'https://mail.example/../', 'https://mail.example/\\', 'https://mail.\nexample',
    'not a URL',
  ])('rejects unsafe or non-origin server input %s', (input) => {
    expect(() => normalizeInstance(input)).toThrow();
  });
});
