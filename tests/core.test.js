import test from 'node:test';
import assert from 'node:assert/strict';
import { normalizeDomain, matches, protectedDomain, webURL, originalURL, lockedURL, domainRules, grantRule, trustedPage } from '../extension/core.js';
const base = 'chrome-extension://abcdefghijklmnopabcdefghijklmnop/';
test('normalizes URLs, www, IDNs, ports, and trailing DNS dots', () => {
  assert.equal(normalizeDomain(' HTTPS://WWW.Example.COM:8443/path?q=1 '), 'example.com');
  assert.equal(normalizeDomain('https://bücher.de'), 'xn--bcher-kva.de');
  assert.equal(normalizeDomain('mail.example.co.uk'), 'mail.example.co.uk');
  assert.equal(normalizeDomain('example.com.'), 'example.com');
});
test('rejects non-web schemes, credentials, IPv6, and malformed input', () => {
  for (const value of ['', 'chrome://settings', 'file:///etc/passwd', 'https://user:pass@example.com', 'https://[::1]', '*.example.com', '-example.com', 'https://exa mple.com']) assert.throws(() => normalizeDomain(value), value);
  assert.equal(webURL('javascript:alert(1)'), null);
});
test('domain matching uses label boundaries and prefers specific domains', () => {
  assert.ok(matches('mail.example.com', 'example.com'));
  assert.ok(matches('EXAMPLE.COM.', 'example.com'));
  assert.ok(!matches('notexample.com', 'example.com'));
  assert.ok(!matches('example.com.attacker.test', 'example.com'));
  assert.equal(protectedDomain('https://a.mail.example.com', ['example.com', 'mail.example.com']), 'mail.example.com');
  assert.equal(protectedDomain('https://attacker.test/?next=example.com', ['example.com']), null);
});
test('lock URL preserves the original path, query, escaping, and fragment', () => {
  const url = 'https://example.com/a%20b?q=%26&next=https://other.test/#route?tab=2';
  assert.equal(originalURL(lockedURL(base, url), base), url);
  assert.equal(originalURL(`${base}locked.html#javascript:alert(1)`, base), null);
  assert.throws(() => lockedURL(base, 'data:text/html,secret'));
});
test('persistent rules redirect main frames and block protected embeds', () => {
  const rules = domainRules(['example.com'], base);
  assert.equal(rules.length, 2);
  assert.equal(rules[0].action.redirect.regexSubstitution, `${base}locked.html#\\0`);
  assert.deepEqual(rules[0].condition.requestDomains, ['example.com']);
  assert.equal(rules[1].action.type, 'block');
  assert.deepEqual(rules[1].condition.excludedResourceTypes, ['main_frame']);
});
test('allow rules apply to one domain across tabs with stable unique IDs', () => {
  const rule = grantRule({ domain: 'example.com' }, 17);
  assert.deepEqual(rule.condition.requestDomains, ['example.com']);
  assert.equal(rule.condition.tabIds, undefined);
  assert.equal(rule.id, 18);
  assert.ok(rule.condition.resourceTypes.includes('main_frame'));
  assert.ok(rule.priority > domainRules(['example.com'], base)[0].priority);
});
test('only named top-level extension pages can authorize changes', () => {
  const pages = ['locked.html', 'settings.html'];
  assert.ok(trustedPage({ url: `${base}locked.html#https://example.com`, frameId: 0 }, base, pages));
  for (const url of ['https://example.com/locked.html', `${base}guard.js`, 'chrome-extension://different/locked.html', `${base}sub/locked.html`]) assert.ok(!trustedPage({ url }, base, pages));
  assert.ok(!trustedPage({ url: `${base}locked.html`, frameId: 2 }, base, pages));
});
