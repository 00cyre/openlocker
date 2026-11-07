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
  const timers = new Map(); let nextTimer = 0;
  let time = Date.now();
  let destination;
  const root = { appendChild(style) { style.isConnected = true; } };
  const document = { visibilityState: 'visible', documentElement: rootExists ? root : null, createElement() { const style = { isConnected: false, remove() { this.isConnected = false; } }; styles.push(style); return style; } };
  vm.runInNewContext(source, {
    document, Date: { now: () => time }, setTimeout: (fn,ms) => {timers.set(++nextTimer,{fn,ms});return nextTimer;}, clearTimeout: id=>timers.delete(id),
    chrome: { runtime: { sendMessage: () => new Promise(resolve => pending.push(resolve)) } },
    location: { replace(url) { destination = url; } },
    MutationObserver: class { constructor(callback) { observers.push(callback); } observe() {} disconnect() {} },
    addEventListener: (type, callback) => { events[type] = callback; }
  });
  return { styles, pending, events, document, timers, now: () => time, advance(ms) { time += ms; }, showRoot() { document.documentElement = root; observers.forEach(fn => fn()); }, destination: () => destination };
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

for (const protectedSite of [false, true]) {
  test(`tab switches do not blank an already allowed ${protectedSite ? 'protected' : 'unprotected'} page`, async () => {
    const g = guard();
    const response = { ok: true, allowed: true, expiresAt: protectedSite ? g.now() + 300000 : null };
    g.pending.shift()(response);
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(g.styles[0].isConnected, false);
    for (let i = 0; i < 100; i++) {
      g.document.visibilityState = 'hidden'; g.events.visibilitychange();
      g.document.visibilityState = 'visible'; g.events.visibilitychange();
      g.events.focus();
      assert.equal(g.styles[0].isConnected, false, 'Switching back must not blank the whole page while authorization is rechecked');
      g.pending.splice(0).forEach(resolve => resolve(response));
      await new Promise(resolve => setImmediate(resolve));
      assert.equal(g.styles[0].isConnected, false);
    }
  });
}

test('a focus recheck cannot postpone the existing deadline or reveal a late response', async () => {
  const g = guard(), expiresAt = g.now() + 300000;
  g.pending.shift()({ ok: true, allowed: true, expiresAt });
  await new Promise(resolve => setImmediate(resolve));
  const deadline = [...g.timers.values()][0];
  g.advance(299999); g.events.focus();
  assert.equal(g.styles[0].isConnected, false);
  assert.ok([...g.timers.values()].includes(deadline), 'The deadline must stay armed during the request');
  g.advance(1); deadline.fn();
  assert.equal(g.styles[0].isConnected, true);
  g.pending.shift()({ ok: true, allowed: true, expiresAt });
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(g.styles[0].isConnected, true, 'The older focus response cannot uncover the expired page');
});

test('returning after expiry covers before awaiting the worker even if the timer was delayed', async () => {
  const g = guard();
  g.pending.shift()({ ok: true, allowed: true, expiresAt: g.now() + 300000 });
  await new Promise(resolve => setImmediate(resolve));
  g.advance(300000); g.events.focus();
  assert.equal(g.styles[0].isConnected, true);
});

test('a quiet recheck still covers immediately on denial or unavailable authorization', async () => {
  for (const response of [{ ok: false }, { ok: true, allowed: false, redirect: 'chrome-extension://test/locked.html' }]) {
    const g = guard();
    g.pending.shift()({ ok: true, allowed: true, expiresAt: g.now() + 300000 });
    await new Promise(resolve => setImmediate(resolve));
    g.events.focus(); g.pending.shift()(response);
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(g.styles[0].isConnected, true);
    assert.equal(g.timers.size, 0);
    if (response.redirect) assert.equal(g.destination(), response.redirect);
  }
});

test('an allowed reply whose deadline passed in transit never reveals the page', async () => {
  const g = guard(), expiresAt = g.now() + 1;
  g.advance(2); g.pending.shift()({ ok: true, allowed: true, expiresAt });
  await new Promise(resolve => setImmediate(resolve));
  assert.equal(g.styles[0].isConnected, true);
  assert.equal([...g.timers.values()][0].ms, 0);
});

test('a worker connection failure covers the page unless a newer check has authorized it', async () => {
  for (const newerCheck of [false, true]) {
    const g = guard(), response = { ok: true, allowed: true, expiresAt: g.now() + 300000 };
    g.pending.shift()(response);
    await new Promise(resolve => setImmediate(resolve));
    g.events.focus(); const failed = g.pending.shift();
    if (newerCheck) {
      g.events.focus(); g.pending.shift()(response);
      await new Promise(resolve => setImmediate(resolve));
    }
    failed(Promise.reject(new Error('Worker disconnected')));
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(g.styles[0].isConnected, !newerCheck);
  }
});

test('moving the clock backwards invalidates the cached authorization before a recheck', async () => {
  const g = guard();
  g.pending.shift()({ ok: true, allowed: true, expiresAt: g.now() + 300000 });
  await new Promise(resolve => setImmediate(resolve));
  g.advance(-1); g.events.focus();
  assert.equal(g.styles[0].isConnected, true);
});

test('the page covers itself and rechecks at its deadline without an alarm or tab switch', async () => {
  const g=guard();g.pending.shift()({ok:true,allowed:true,expiresAt:g.now()+300000});
  await new Promise(resolve=>setImmediate(resolve));
  assert.equal(g.styles[0].isConnected,false);assert.equal(g.timers.size,1);
  g.advance(300000); [...g.timers.values()][0].fn();
  assert.equal(g.styles[0].isConnected,true);assert.equal(g.pending.length,1);
  g.pending.shift()({ok:true,allowed:false,redirect:'chrome-extension://test/locked.html'});
  await new Promise(resolve=>setImmediate(resolve));assert.equal(g.styles[0].isConnected,true);
});
