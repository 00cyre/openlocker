import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import { readFileSync } from 'node:fs';
const source = readFileSync(new URL('../extension/guard.js', import.meta.url), 'utf8');
function guard({ rootExists = true } = {}) {
  const styles = [];
  const observers = [];
  const events = {};
  const pending = [];
  let destination;
  const root = { appendChild(style) { style.isConnected = true; } };
  const document = { documentElement: rootExists ? root : null, createElement() { const style = { isConnected: false, remove() { this.isConnected = false; } }; styles.push(style); return style; } };
  vm.runInNewContext(source, {
    document,
    chrome: { runtime: { sendMessage: () => new Promise(resolve => pending.push(resolve)) } },
    location: { replace(url) { destination = url; } },
    MutationObserver: class { constructor(callback) { observers.push(callback); } observe() {} disconnect() {} },
    addEventListener: (type, callback) => { events[type] = callback; }
  });
  return { styles, pending, events, document, showRoot() { document.documentElement = root; observers.forEach(fn => fn()); }, destination: () => destination };
}
test('covers before authorization and uncovers allowed documents', async () => {
  const g = guard();
  assert.equal(g.styles[0].isConnected, true);
  g.pending.shift()({ ok: true, allowed: true });
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(g.styles[0].isConnected, false);
});
test('denied and unavailable decisions never reveal content', async () => {
  for (const response of [{ ok: false }, { ok: true, allowed: false, redirect: 'chrome-extension://test/locked.html' }]) {
    const g = guard();
    g.pending.shift()(response);
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(g.styles[0].isConnected, true);
    if (response.redirect) assert.equal(g.destination(), response.redirect);
  }
});
test('an early allowed decision is not undone by a late document root', async () => {
  const g = guard({ rootExists: false });
  g.pending.shift()({ ok: true, allowed: true });
  await new Promise(resolve => setImmediate(resolve));
  g.showRoot();
  assert.equal(g.styles[0].isConnected, false);
});
test('pagehide covers a cached page and pageshow requires a new decision', async () => {
  const g = guard();
  g.pending.shift()({ ok: true, allowed: true });
  await new Promise(resolve => setImmediate(resolve));
  g.events.pagehide();
  assert.equal(g.styles[0].isConnected, true);
  g.events.pageshow();
  assert.equal(g.pending.length, 1);
  assert.equal(g.styles[0].isConnected, true);
});
test('a late allowed response cannot uncover a page after pagehide', async () => {
  const g = guard();
  g.events.pagehide();
  g.pending.shift()({ ok: true, allowed: true });
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(g.styles[0].isConnected, true);
});
