import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import assert from 'node:assert/strict';
const manifest = JSON.parse(readFileSync('extension/manifest.json'));
assert.equal(manifest.manifest_version, 3);
const id = [...createHash('sha256').update(Buffer.from(manifest.key, 'base64')).digest().subarray(0, 16)].map(b => String.fromCharCode(97 + (b >> 4), 97 + (b & 15))).join('');
assert.equal(id, readFileSync('extension-id.txt', 'utf8').trim());
assert.ok(readFileSync('native/Config.swift', 'utf8').includes(`chrome-extension://${id}/`));
for (const file of readdirSync('extension').filter(name => name.endsWith('.js'))) execFileSync(process.execPath, ['--check', `extension/${file}`]);
for (const icon of Object.values(manifest.icons)) assert.ok(existsSync(`extension/${icon}`), `Missing ${icon}`);
for (const file of ['popup.html', 'locked.html', 'settings.html']) {
  const html = readFileSync(`extension/${file}`, 'utf8');
  assert.ok(!/<script(?![^>]*\bsrc=)[^>]*>/i.test(html), 'Inline script violates extension CSP');
  for (const [, src] of html.matchAll(/(?:src|href)="([^"#]+)"/g)) {
    if (!src.includes('://')) assert.ok(existsSync(`extension/${src}`), `Missing ${src}`);
  }
}
console.log('Manifest, scripts, page assets, and native origin are consistent.');
