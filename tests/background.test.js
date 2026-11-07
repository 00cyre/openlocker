import test from 'node:test';
import assert from 'node:assert/strict';
import { LockedTabs } from '../extension/locked-tabs.js';

const ID = 'abcdefghijklmnopabcdefghijklmnop';
const base = `chrome-extension://${ID}/`;
const event = () => { const listeners = []; return { addListener(fn) { listeners.push(fn); }, fire(...args) { for (const fn of listeners) fn(...args); }, listeners }; };
const copy = value => structuredClone(value);
// Model the documented Chrome matching defaults at the navigation boundary.
// Omitted OR empty resource-type filters EXCLUDE main_frame. Chromium's
// ComputeElementTypes uses the default mask when both computed masks are empty.
// https://developer.chrome.com/docs/extensions/reference/api/declarativeNetRequest#type-RuleCondition
// https://github.com/chromium/chromium/blob/main/extensions/browser/api/declarative_net_request/indexed_rule.cc
function networkRule(rules, { url, type = 'main_frame', tabId }) {
  const host = new URL(url).hostname;
  return rules.filter(({ condition: c }) =>
    (!c.tabIds || c.tabIds.includes(tabId)) &&
    (!c.requestDomains || c.requestDomains.some(d => host === d || host.endsWith(`.${d}`))) &&
    (!c.regexFilter || new RegExp(c.regexFilter).test(url)) &&
    (c.resourceTypes?.length ? c.resourceTypes.includes(type) : c.excludedResourceTypes?.length ? !c.excludedResourceTypes.includes(type) : type !== 'main_frame')
  ).sort((a, b) => b.priority - a.priority)[0];
}
function storage(initial = {}) {
  let data = copy(initial);
  return { async get(defaults) { return copy({ ...defaults, ...data }); }, async set(value) { Object.assign(data, copy(value)); }, async setAccessLevel() {} };
}
let counter = 0;
async function harness({ domains = ['example.com'], grants = [], tabs, native, network = false, idleSeconds = 0, localData, dynamicRules = [], recoveryReady = false, startTime = 1_000_000 } = {}) {
  let time = startTime;
  const alarms = new Map();
  let focusedWindow = 1;
  let dynamic = copy(dynamicRules);
  let sessionRules = [];
  let detectionInterval;
  let reloads = 0;
  const tabMap = new Map((tabs || [{ id: 1, active: true, url: `${base}locked.html#https://example.com/private`, windowId: 1 }]).map(t => [t.id, copy(t)]));
  let nextTab = Math.max(0, ...tabMap.keys()) + 1;
  let nextWindow = Math.max(0, ...[...tabMap.values()].map(t => t.windowId)) + 1;
  const api = {
    runtime: { id: ID, getManifest: () => ({version:'0.1.13'}), reload() { reloads++; }, getURL: path => base + path, onMessage: event(), onStartup: event(), onInstalled: event(), openOptionsPage: async () => {}, sendNativeMessage: native || (async (_, message) => ({ id: message.id, success: true, available: true })) },
    action: { text: '', title: '', async setBadgeText({text}) { this.text=text; }, async setBadgeBackgroundColor() {}, async setTitle({title}) { this.title=title; } },
    storage: { local: storage(localData ?? { domains }), session: storage({ grants: grants.map(g => ({ lastActivity: time, ...g })), recoveryReady }) },
    declarativeNetRequest: {
      getDynamicRules: async () => copy(dynamic),
      getSessionRules: async () => copy(sessionRules),
      updateDynamicRules: async ({ addRules }) => { dynamic = copy(addRules); },
      updateSessionRules: async ({ addRules }) => { sessionRules = copy(addRules); }
    },
    tabs: {
      create: async data => { const tab = { id: nextTab++, windowId: 1, index: 0, active: false, ...data }; tabMap.set(tab.id, tab); return copy(tab); },
      query: async (query = {}) => [...tabMap.values()].filter(t => (!query.active || t.active) && (!query.windowId || t.windowId === query.windowId)).map(copy),
      get: async id => { if (!tabMap.has(id)) throw Error('No tab'); return copy(tabMap.get(id)); },
      update: async (id, data) => {
        if (!tabMap.has(id)) throw Error('No tab');
        if (network && /^https?:/.test(data.url || '')) {
          const rule = networkRule([...dynamic, ...sessionRules], { url: data.url, tabId: id });
          if (rule?.action.type === 'redirect') data = { ...data, url: rule.action.redirect.regexSubstitution.replace('\\0', data.url) };
        }
        Object.assign(tabMap.get(id), data); return copy(tabMap.get(id));
      },
      onActivated: event(), onUpdated: event(), onRemoved: event(), onMoved: event(), onAttached: event(), onDetached: event()
    },
    alarms: { onAlarm: event(), create: async (name, info) => { alarms.set(name, {...info,scheduledTime:info.when}); }, clear: async name => alarms.delete(name), get: async name => alarms.get(name) },
    windows: { get: async id => ({id,focused:id===focusedWindow}), WINDOW_ID_NONE: -1, onFocusChanged: event(), create: async ({ url }) => {
      const id = nextWindow++;
      const tab = await api.tabs.create({ url, windowId: id });
      return { id, tabs: [tab] };
    } },
    webNavigation: { onCommitted: event() },
    idle: {
      onStateChanged: event(),
      setDetectionInterval(seconds) { detectionInterval = seconds; },
      queryState: async seconds => idleSeconds >= seconds ? 'idle' : 'active'
    }
  };
  globalThis.chrome = api;
  const realNow = Date.now;
  Date.now = () => time;
  try { await import(`../extension/background.js?test=${counter++}`); } finally { Date.now = realNow; }
  const sender = (page = 'locked.html', tabId = 1) => ({ id: ID, frameId: 0, url: page === 'locked.html' ? tabMap.get(tabId).url : `${base}${page}`, tab: copy(tabMap.get(tabId)) });
  const send = (message, source = sender()) => new Promise(resolve => api.runtime.onMessage.listeners[0](message, source, resolve));
  await send({ type: 'STATUS' }, sender('settings.html', tabMap.keys().next().value));
  return {
    api, send, sender, tabMap, webSender: (id = 1, frameId = 0) => ({ id: ID, frameId, url: tabMap.get(id).url, tab: copy(tabMap.get(id)) }), rules: () => ({ dynamic, sessionRules }),
    now: () => time,
    focusWindow(id) { focusedWindow=id; api.windows.onFocusChanged.fire(id); },
    async flush() { for(let i=0;i<4;i++) await new Promise(resolve=>setImmediate(resolve)); },
    interval: () => detectionInterval,
    reloads: () => reloads,
    advance(seconds, notify = true, notifyAlarms = true) {
      time += seconds * 1000;
      if (notifyAlarms) for(const [name, info] of alarms) if(info.when<=time) { alarms.delete(name); api.alarms.onAlarm.fire({name}); }
      const before = idleSeconds; idleSeconds += seconds;
      if (notify && before < detectionInterval && idleSeconds >= detectionInterval) api.idle.onStateChanged.fire('idle');
    },
    input() { const wasIdle = idleSeconds >= detectionInterval; idleSeconds = 0; if (wasIdle) api.idle.onStateChanged.fire('active'); }
  };
}

test('successful native authentication unlocks a domain across tabs', async () => {
  const h = await harness();
  const result = await h.send({ type: 'UNLOCK' });
  assert.equal(result.ok, true);
  assert.equal(h.tabMap.get(1).url, 'https://example.com/private');
  assert.equal(h.rules().sessionRules[0].condition.tabIds, undefined);
  assert.deepEqual(h.rules().sessionRules[0].condition.requestDomains, ['example.com']);
});
test('reload restores locked tabs closed by Chrome without losing duplicates or protected sites', async () => {
  const locked = `${base}locked.html#http://127.0.0.1:4173/private?draft=1#section`;
  const h = await harness({ domains: ['127.0.0.1'], tabs: [
    { id: 1, active: true, url: locked, windowId: 1, index: 0, pinned: true },
    { id: 2, active: false, url: locked, windowId: 1, index: 1, pinned: false },
    { id: 3, active: false, url: 'https://unrelated.test/', windowId: 1, index: 2 }
  ] });
  // Chromium closes extension-origin tabs when unloading the extension. The
  // next worker only sees the unrelated web tab; local storage/rules survive.
  // https://issues.chromium.org/issues/41189391
  const reloaded = await harness({ localData: await h.api.storage.local.get({}), dynamicRules: h.rules().dynamic,
    tabs: [...h.tabMap.values()].filter(t => !t.url.startsWith(base)) });
  reloaded.api.runtime.onInstalled.fire({ reason: 'update' });
  const status = await reloaded.send({ type: 'STATUS' }, reloaded.sender('settings.html', 3));
  assert.deepEqual(status.domains, ['127.0.0.1']);
  assert.equal([...reloaded.tabMap.values()].filter(t => t.url === locked).length, 2, 'Both locked tabs must return, including identical URLs');
  assert.equal(reloaded.tabMap.get(3).url, 'https://unrelated.test/');
});
test('missing domain settings recover from persistent protection rules before startup rewrites them', async () => {
  const h = await harness({ domains: ['127.0.0.1', 'example.com'] });
  const reloaded = await harness({ localData: {}, dynamicRules: h.rules().dynamic });
  const status = await reloaded.send({ type: 'STATUS' }, reloaded.sender('settings.html'));
  assert.deepEqual(status.domains, ['127.0.0.1', 'example.com']);
  assert.equal(reloaded.rules().dynamic.length, 4);
});
test('backup recovers a missing domain list, but an intentional empty list remains empty', async () => {
  for (const domains of [undefined, []]) {
    const localData = { domainsBackup: { version: 1, domains: ['example.com'] } };
    if (domains) localData.domains = domains;
    const h = await harness({ localData });
    const status = await h.send({ type: 'STATUS' }, h.sender('settings.html'));
    assert.deepEqual(status.domains, domains || ['example.com']);
  }
});
test('rule recovery supports the full 500-domain limit despite duplicate rule entries', async () => {
  const domains = Array.from({ length: 500 }, (_, index) => `site${index}.test`).sort();
  const h = await harness({ domains });
  const recovered = await harness({ localData: {}, dynamicRules: h.rules().dynamic });
  assert.deepEqual((await recovered.api.storage.local.get({})).domains, domains);
});
test('ordinary worker restart or deliberate tab close does not resurrect tabs', async () => {
  const h = await harness();
  const saved = await h.api.storage.local.get({});
  const worker = await harness({ localData: saved, tabs: [], recoveryReady: true });
  assert.equal(worker.tabMap.size, 0);
  const another = await harness();
  another.tabMap.delete(1);
  another.api.tabs.onRemoved.fire(1, { windowId: 1, isWindowClosing: false });
  await another.send({ type: 'STATUS' }, another.sender('settings.html'));
  const reloaded = await harness({ localData: await another.api.storage.local.get({}), tabs: [] });
  assert.equal(reloaded.tabMap.size, 0);
});
test('reload restores a window that contained only locked tabs, preserving pinning', async () => {
  const locked = `${base}locked.html#https://example.com/private`;
  const h = await harness({ tabs: [{ id: 4, url: locked, windowId: 9, index: 0, active: true, pinned: true },
    { id: 5, url: locked, windowId: 9, index: 1, active: false, pinned: false }] });
  const restored = await harness({ tabs: [], localData: await h.api.storage.local.get({}) });
  const tabs = [...restored.tabMap.values()];
  assert.equal(tabs.length, 2);
  assert.equal(tabs[0].windowId, tabs[1].windowId);
  assert.equal(tabs[0].pinned, true);
  assert.equal(tabs[0].url, locked);
});
test('recovery matches restored tab occurrences and never overwrites a surviving navigation', async () => {
  const locked = `${base}locked.html#https://example.com/private`;
  const h = await harness();
  const saved = await h.api.storage.local.get({});
  const restored = await harness({ localData: saved, tabs: [{ id: 50, url: locked, windowId: 20, index: 0 }] });
  assert.equal(restored.tabMap.size, 1);
  const navigated = await harness({ localData: saved, tabs: [{ id: 1, url: 'https://unrelated.test/', windowId: 1, index: 0 }] });
  assert.equal(navigated.tabMap.size, 1);
  assert.equal(navigated.tabMap.get(1).url, 'https://unrelated.test/');
});
test('button-driven update keeps locked tab IDs and protected settings through reload', async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async url => ({ ok: true, json: async () => url.startsWith(base) ? { managed: true } : {
    tag_name: 'v0.9.0', draft: false, prerelease: false,
    assets: [{ name: 'OpenLocker-0.9.0-macOS.dmg', size: 1000,
      browser_download_url: 'https://github.com/00cyre/openlocker/releases/download/v0.9.0/OpenLocker-0.9.0-macOS.dmg' }]
  } });
  try {
    const h = await harness({ native: async (_, m) => ({ id: m.id, success: true, supportsUpdates: true, version: '0.9.0' }) });
    h.api.runtime.getManifest = () => ({ version: '0.1.13' });
    const result = await h.send({ type: 'INSTALL_UPDATE' }, h.sender('settings.html'));
    assert.equal(result.ok, true, result.error);
    assert.equal(result.updated, true);
    assert.equal(h.reloads(), 1, 'The background must finish the reload even if the popup has closed');
    assert.ok(h.tabMap.get(1).url.startsWith('about:blank#openlocker-'), 'The tab must leave the extension origin before reload');
    const surviving = [...h.tabMap.values()].filter(tab => !tab.url.startsWith(base));
    const reloaded = await harness({ localData: await h.api.storage.local.get({}), tabs: surviving });
    assert.equal(reloaded.tabMap.size, 1);
    assert.equal(reloaded.tabMap.get(1).url, `${base}locked.html#https://example.com/private`);
    assert.deepEqual((await reloaded.send({ type: 'STATUS' })).domains, ['example.com']);
    assert.equal(reloaded.rules().sessionRules.length, 0, 'Recovery never authenticates a domain');
    const closed = await harness({ native: async (_, m) => ({ id: m.id, success: true, supportsUpdates: true, version: '0.9.0' }) });
    closed.api.runtime.getManifest = () => ({ version: '0.1.13' });
    closed.api.runtime.onMessage.listeners[0]({ type: 'INSTALL_UPDATE' }, closed.sender('popup.html'), () => { throw Error('Popup closed'); });
    for (let attempt = 0; attempt < 100 && !closed.reloads(); attempt++) await new Promise(resolve => setImmediate(resolve));
    assert.equal(closed.reloads(), 1, 'A disconnected popup must not strand parked tabs');
  } finally { globalThis.fetch = originalFetch; }
});
test('failed restoration keeps its recovery record and succeeds once the window API recovers', async () => {
  const h = await harness();
  const saved = await h.api.storage.local.get({});
  h.tabMap.clear();
  const createWindow = h.api.windows.create;
  h.api.windows.create = async () => { throw Error('Window creation temporarily unavailable'); };
  const journal = new LockedTabs(h.api, base);
  await journal.restore(['example.com']);
  assert.deepEqual((await h.api.storage.local.get({})).lockedTabs, saved.lockedTabs);
  h.api.windows.create = createWindow;
  await journal.restore(['example.com']);
  assert.equal(h.tabMap.size, 1);
  await journal.restore(['example.com']);
  assert.equal(h.tabMap.size, 1, 'Retry must not duplicate successful recovery');
});
test('closing a tab during update preparation does not resurrect it or erase settings', async () => {
  const h = await harness();
  const update = h.api.tabs.update;
  h.api.tabs.update = async (id, data) => {
    if (data.url.startsWith('about:blank')) { h.tabMap.delete(id); throw Error('Tab closed'); }
    return update(id, data);
  };
  const journal = new LockedTabs(h.api, base);
  await assert.rejects(journal.prepareReload(['example.com']), /Tab closed/);
  assert.equal(h.tabMap.size, 0);
  const saved = await h.api.storage.local.get({});
  assert.deepEqual(saved.domains, ['example.com']);
  assert.deepEqual(saved.lockedTabs, []);
});
test('failed rule changes preserve both website-list copies', async () => {
  const h = await harness();
  h.api.declarativeNetRequest.updateDynamicRules = async () => { throw Error('Rule update failed'); };
  const result = await h.send({ type: 'LOCK_DOMAIN', domain: 'new.test' }, h.sender('settings.html'));
  assert.equal(result.ok, false);
  const saved = await h.api.storage.local.get({});
  assert.deepEqual(saved.domains, ['example.com']);
  assert.deepEqual(saved.domainsBackup.domains, ['example.com']);
});
test('successful Touch ID reaches a localhost page instead of redirecting back to the lock screen', async () => {
  const url = 'http://127.0.0.1:4173/private';
  const h = await harness({ network: true, domains: ['127.0.0.1'], tabs: [{ id: 1, active: true, windowId: 1, url: `${base}locked.html#${url}` }] });
  const result = await h.send({ type: 'UNLOCK' });
  assert.equal(result.ok, true, result.error);
  assert.equal(h.tabMap.get(1).url, url, 'The unlock must allow the main-frame navigation, otherwise the new lock page automatically prompts again');
  const rules = [...h.rules().dynamic, ...h.rules().sessionRules];
  for (const type of ['main_frame', 'sub_frame', 'script', 'xmlhttprequest', 'websocket']) {
    assert.equal(networkRule(rules, { url, tabId: 1, type }).action.type, 'allow', type);
  }
  assert.equal(networkRule(rules, { url, tabId: 2 }).action.type, 'allow', 'The authenticated domain stays open across tabs');
  await h.send({ type: 'LOCK_ALL' }, h.sender('settings.html'));
  assert.ok(h.tabMap.get(1).url.startsWith(base), 'Relocking still redirects the page');
});
test('cancellation leaves persistent rules and creates no grant', async () => {
  const h = await harness({ native: async (_, message) => ({ id: message.id, success: false, message: 'Cancelled.' }) });
  assert.equal((await h.send({ type: 'UNLOCK' })).ok, false);
  assert.equal(h.rules().sessionRules.length, 0);
  assert.equal(h.rules().dynamic.length, 2);
  assert.ok(h.tabMap.get(1).url.startsWith(base));
});
test('an unavailable inactivity clock revokes access and rejects new unlocks', async () => {
  const h = await harness();
  assert.equal((await h.send({ type: 'UNLOCK' })).ok, true);
  h.api.idle.queryState = async () => { throw Error('Idle state unavailable'); };
  const status = await h.send({ type: 'STATUS' }, h.sender('settings.html'));
  assert.equal(status.unlocked, false);
  assert.equal(h.rules().sessionRules.length, 0);
  assert.ok(h.tabMap.get(1).url.startsWith(base));
  assert.equal((await h.send({ type: 'UNLOCK' })).ok, false);
});
test('missing helper and mismatched request IDs never unlock', async () => {
  for (const native of [async () => { throw Error('No native host'); }, async () => ({ id: 'wrong', success: true })]) {
    const h = await harness({ native });
    assert.equal((await h.send({ type: 'UNLOCK' })).ok, false);
    assert.equal(h.rules().sessionRules.length, 0);
  }
});
test('web page cannot mutate rules or ask for someone else’s grant', async () => {
  const h = await harness();
  const contentSender = { id: ID, url: 'https://example.com/private', frameId: 0, tab: { id: 1 } };
  for (const type of ['UNLOCK', 'LOCK_DOMAIN', 'REMOVE_DOMAIN', 'LOCK_ALL', 'HELPER_STATUS', 'UPDATE_STATUS', 'INSTALL_UPDATE']) assert.equal((await h.send({ type, domain: 'example.com' }, contentSender)).ok, false, type);
  const guard = await h.send({ type: 'GUARD', tabId: 2 }, contentSender);
  assert.equal(guard.allowed, false);
  assert.ok(guard.redirect.startsWith(base));
});
test('tab and window switching preserve the domain session', async () => {
  const h = await harness();
  await h.send({ type: 'UNLOCK' });
  h.tabMap.get(1).active = false;
  h.api.tabs.onActivated.fire({ tabId: 2 });
  h.api.windows.onFocusChanged.fire(h.api.windows.WINDOW_ID_NONE);
  h.api.windows.onFocusChanged.fire(2);
  await h.send({ type: 'STATUS' }, h.sender('settings.html'));
  assert.equal(h.rules().sessionRules.length, 1);
  assert.equal(h.tabMap.get(1).url, 'https://example.com/private');
});
test('late successful authentication cannot override a concurrent lock', async () => {
  let resolve;
  const h = await harness({ native: (_, message) => new Promise(done => { resolve = () => done({ id: message.id, success: true }); }) });
  const unlocking = h.send({ type: 'UNLOCK' });
  await new Promise(done => setImmediate(done));
  await h.send({ type: 'LOCK_ALL' }, h.sender('settings.html'));
  resolve();
  assert.equal((await unlocking).ok, false);
  assert.equal(h.rules().sessionRules.length, 0);
});
test('navigating away while authenticating invalidates the response', async () => {
  let resolve;
  const h = await harness({ native: (_, message) => new Promise(done => { resolve = () => done({ id: message.id, success: true }); }) });
  const unlocking = h.send({ type: 'UNLOCK' });
  await new Promise(done => setImmediate(done));
  h.tabMap.get(1).url = 'https://other.test/';
  resolve();
  assert.equal((await unlocking).ok, false);
  assert.equal(h.rules().sessionRules.length, 0);
});
test('concurrent additions do not lose protected domains', async () => {
  const h = await harness();
  const results = await Promise.all(['a.test', 'b.test'].map(domain => h.send({ type: 'LOCK_DOMAIN', domain }, h.sender('settings.html'))));
  assert.ok(results.every(r => r.ok));
  assert.deepEqual((await h.send({ type: 'STATUS' }, h.sender('settings.html'))).domains, ['a.test', 'b.test', 'example.com']);
});
test('removing protection requires fresh Touch ID', async () => {
  let calls = 0;
  const h = await harness({ native: async (_, message) => { calls++; return { id: message.id, success: false }; } });
  assert.equal((await h.send({ type: 'REMOVE_DOMAIN', domain: 'example.com' }, h.sender('settings.html'))).ok, false);
  assert.equal(calls, 1);
  assert.equal(h.rules().dynamic.length, 2);
});
test('startup and Mac screen lock clear existing grants', async () => {
  for (const eventName of ['startup', 'screen']) {
    const h = await harness();
    await h.send({ type: 'UNLOCK' });
    if (eventName === 'startup') h.api.runtime.onStartup.fire(); else h.api.idle.onStateChanged.fire('locked');
    await h.send({ type: 'STATUS' }, h.sender('settings.html'));
    assert.equal(h.rules().sessionRules.length, 0);
    assert.ok(h.tabMap.get(1).url.startsWith(base));
  }
});
test('a missing tab during navigation does not retain an allow rule', async () => {
  const h = await harness();
  h.api.tabs.update = async () => { throw new Error('Tab closed'); };
  assert.equal((await h.send({ type: 'UNLOCK' })).ok, false);
  assert.equal(h.rules().sessionRules.length, 0);
});
test('service worker restart retains domain grants even for background or closed tabs', async () => {
  const h = await harness({
    grants: [{ domain: 'example.com' }, { domain: 'removed.test' }, { tabId: 8, domain: 'example.com' }],
    tabs: [{ id: 1, active: false, url: 'https://example.com/private', windowId: 1 }]
  });
  assert.equal(h.rules().sessionRules.length, 1);
  assert.equal(h.tabMap.get(1).url, 'https://example.com/private');
});
test('leaving a domain or closing its tab preserves the domain session', async () => {
  const h = await harness();
  await h.send({ type: 'UNLOCK' });
  h.tabMap.get(1).url = 'https://other.test/';
  h.api.tabs.onUpdated.fire(1, { url: 'https://other.test/' });
  await h.send({ type: 'STATUS' }, h.sender('settings.html'));
  assert.equal(h.rules().sessionRules.length, 1);
  h.api.tabs.onRemoved.fire(1);
  await h.send({ type: 'STATUS' }, h.sender('settings.html'));
  assert.equal(h.rules().sessionRules.length, 1);
});
test('unlocking a parent domain also authorizes its protected child', async () => {
  const h = await harness({ domains: ['example.com', 'mail.example.com'] });
  await h.send({ type: 'UNLOCK' });
  h.tabMap.get(1).url = 'https://mail.example.com/inbox';
  const state = await h.send({ type: 'STATUS' }, h.sender('settings.html'));
  assert.equal(state.unlocked, true);
  assert.equal((await h.send({ type: 'GUARD' }, { id: ID, frameId: 0, url: h.tabMap.get(1).url, tab: { id: 1 } })).allowed, true);
});

test('five minutes without site input revokes grants, and input in that site restarts its timer', async () => {
  const h = await harness();
  assert.equal(h.interval(), 300);
  await h.send({ type: 'UNLOCK' });
  for (let i = 0; i < 4; i++) {
    h.advance(299);
    assert.equal((await h.send({ type: 'STATUS' }, h.sender('settings.html'))).unlocked, true);
    h.input();
    await h.send({ type: 'ACTIVITY' }, h.webSender());
  }
  h.advance(299);
  assert.equal((await h.send({ type: 'STATUS' }, h.sender('settings.html'))).unlocked, true);
  h.advance(1);
  assert.equal((await h.send({ type: 'STATUS' }, h.sender('settings.html'))).unlocked, false);
  assert.equal(h.rules().sessionRules.length, 0);
  assert.ok(h.tabMap.get(1).url.startsWith(base));
  h.input();
  assert.equal((await h.send({ type: 'STATUS' }, h.sender('settings.html'))).unlocked, false, 'Activity must not replace Touch ID');
});

test('worker recovery and a guard query both fail closed when already idle', async () => {
  const h = await harness({ idleSeconds: 300, grants: [{ domain: 'example.com' }], tabs: [{ id: 1, active: true, url: 'https://example.com/private', windowId: 1 }] });
  assert.equal(h.rules().sessionRules.length, 0);
  h.input();
  await h.send({ type: 'UNLOCK' });
  h.advance(300, false); // Query catches timeout even before its state-change event is handled.
  const result = await h.send({ type: 'GUARD' }, { id: ID, frameId: 0, url: 'https://example.com/private', tab: { id: 1 } });
  assert.equal(result.allowed, false);
  assert.equal(h.rules().sessionRules.length, 0);
});

test('idle invalidates pending authentication even if input resumes before its response', async () => {
  let resolve;
  const h = await harness({ native: (_, message) => new Promise(done => { resolve = () => done({ id: message.id, success: true }); }) });
  const unlocking = h.send({ type: 'UNLOCK' });
  await new Promise(done => setImmediate(done));
  h.advance(300);
  await h.send({ type: 'STATUS' }, h.sender('settings.html'));
  h.input(); resolve();
  assert.equal((await unlocking).ok, false);
  assert.equal(h.rules().sessionRules.length, 0);
});

test('an existing lock page for an authenticated domain resumes without another fingerprint', async () => {
  let calls = 0;
  const h = await harness({ native: async (_, message) => { calls++; return { id: message.id, success: true }; } });
  await h.send({ type: 'UNLOCK' });
  h.tabMap.set(2, { id: 2, active: true, windowId: 2, url: `${base}locked.html#https://example.com/other` });
  assert.equal((await h.send({ type: 'UNLOCK' }, h.sender('locked.html', 2))).ok, true);
  assert.equal(h.tabMap.get(2).url, 'https://example.com/other');
  assert.equal(calls, 1);
});

test('an authenticated domain does not unlock another protected domain', async () => {
  const h = await harness({ domains: ['example.com', 'other.test'], network: true });
  await h.send({ type: 'UNLOCK' });
  assert.equal(networkRule([...h.rules().dynamic, ...h.rules().sessionRules], { url: 'https://other.test/', tabId: 1 }).action.type, 'redirect');
});

test('returning focus from Touch ID to the same tab does not cancel its unlock', async () => {
  let resolve;
  const h = await harness({ native: (_, message) => new Promise(done => { resolve = () => done({ id: message.id, success: true }); }) });
  const unlocking = h.send({ type: 'UNLOCK' });
  await new Promise(done => setImmediate(done));
  h.api.windows.onFocusChanged.fire(h.api.windows.WINDOW_ID_NONE);
  h.api.windows.onFocusChanged.fire(1);
  await h.send({ type: 'STATUS' }, h.sender('settings.html'));
  resolve();
  const result = await unlocking;
  assert.equal(result.ok, true, result.error);
  assert.equal(h.tabMap.get(1).url, 'https://example.com/private');
});

test('switching away and back during Touch ID still cancels the unlock', async () => {
  let resolve;
  const h = await harness({ native: (_, message) => new Promise(done => { resolve = () => done({ id: message.id, success: true }); }) });
  const unlocking = h.send({ type: 'UNLOCK' });
  await new Promise(done => setImmediate(done));
  h.api.tabs.onActivated.fire({ tabId: 2 });
  h.api.tabs.onActivated.fire({ tabId: 1 });
  await h.send({ type: 'STATUS' }, h.sender('settings.html'));
  resolve();
  assert.equal((await unlocking).ok, false);
  assert.equal(h.rules().sessionRules.length, 0);
});

test('navigating away and back during Touch ID cancels the old unlock', async () => {
  let resolve;
  const h = await harness({ native: (_, message) => new Promise(done => { resolve = () => done({ id: message.id, success: true }); }) });
  const unlocking = h.send({ type: 'UNLOCK' });
  await new Promise(done => setImmediate(done));
  h.api.tabs.onUpdated.fire(1, { url: 'https://other.test/' });
  h.api.tabs.onUpdated.fire(1, { url: h.tabMap.get(1).url });
  await h.send({ type: 'STATUS' }, h.sender('settings.html'));
  resolve();
  assert.equal((await unlocking).ok, false);
  assert.equal(h.rules().sessionRules.length, 0);
});

test('locking retains each original page title through reload and restored tab IDs', async () => {
  const url = 'https://example.com/private';
  const h = await harness({tabs:[{id:1,windowId:1,active:true,url,title:'Budget · Project A',favIconUrl:'https://example.com/favicon.ico'}]});
  assert.equal((await h.send({type:'STATUS'})).title,'Budget · Project A');
  h.tabMap.get(1).title = 'Site locked · OpenLocker';
  h.api.tabs.onUpdated.fire(1,{title:'Site locked · OpenLocker'},copy(h.tabMap.get(1)));
  assert.equal((await h.send({type:'STATUS'})).title,'Budget · Project A');
  const reloaded = await harness({localData:await h.api.storage.local.get({}),tabs:[]});
  const tabId=[...reloaded.tabMap.keys()][0];
  assert.equal((await reloaded.send({type:'STATUS'},reloaded.sender('locked.html',tabId))).title,'Budget · Project A');
  assert.equal(reloaded.rules().sessionRules.length,0);
});
test('titles follow live page changes and never carry across a different destination', async () => {
  const url='https://example.com/private';
  const h=await harness({grants:[{domain:'example.com'}],tabs:[{id:1,windowId:1,active:true,url,title:'Old title'}]});
  h.tabMap.get(1).title='New title';
  h.api.tabs.onUpdated.fire(1,{title:'New title'},copy(h.tabMap.get(1)));
  await h.send({type:'LOCK_ALL'},h.sender('settings.html'));
  assert.equal((await h.send({type:'STATUS'})).title,'New title');
  h.tabMap.get(1).url=`${base}locked.html#https://example.com/different`;
  assert.equal((await h.send({type:'STATUS'})).title,null);
});
test('duplicate destinations keep distinct titles when Chrome restores their tab IDs', async () => {
  const url='https://example.com/private';
  const h=await harness({tabs:[{id:1,windowId:1,index:0,url,title:'First draft'},{id:2,windowId:1,index:1,url,title:'Second draft'}]});
  const saved=await h.api.storage.local.get({});
  const restored=await harness({localData:saved,tabs:[{id:10,windowId:1,index:0,url:`${base}locked.html#${url}`},{id:11,windowId:1,index:1,url:`${base}locked.html#${url}`} ]});
  assert.equal((await restored.send({type:'STATUS'},restored.sender('locked.html',10))).title,'First draft');
  assert.equal((await restored.send({type:'STATUS'},restored.sender('locked.html',11))).title,'Second draft');
});
test('closing a tab drops its saved title and malformed optional metadata does not disable locking', async () => {
  const h=await harness({tabs:[{id:1,windowId:1,url:'https://example.com/private',title:'Private draft'}]});
  h.tabMap.delete(1); h.api.tabs.onRemoved.fire(1,{windowId:1,isWindowClosing:false});
  await h.send({type:'STATUS'},h.sender('settings.html'));
  assert.deepEqual((await h.api.storage.local.get({})).tabTitles,[]);
  for(const tabTitles of [null,{},[null,{id:1,url:'https://example.com/private',title:{}}]]) {
    const malformed=await harness({localData:{domains:['example.com'],tabTitles}});
    assert.equal((await malformed.send({type:'STATUS'})).ok,true);
    assert.equal(malformed.rules().dynamic.length,2);
  }
});
test('a pending navigation does not save the old document title for the new URL', async () => {
  const h=await harness({tabs:[{id:1,windowId:1,url:'https://unrelated.test/',pendingUrl:'https://example.com/private',title:'Unrelated page',status:'loading'}]});
  assert.equal((await h.send({type:'STATUS'})).title,null);
});


test('an unused website expires while the user continues working elsewhere', async () => {
  const h=await harness(); await h.send({type:'UNLOCK'});
  for(let i=0;i<5;i++) { h.advance(60); h.input(); await h.flush(); }
  assert.equal(h.rules().sessionRules.length,0,'Activity outside this site must not keep its grant alive');
  assert.ok(h.tabMap.get(1).url.startsWith(base),'The expiration alarm must cover the tab without a STATUS request');
});

test('input renews only its website, including input inside a frame', async () => {
  const h=await harness({domains:['example.com','other.test'],grants:[{domain:'example.com'},{domain:'other.test'}],tabs:[
    {id:1,windowId:1,active:true,url:'https://example.com/edit'},
    {id:2,windowId:1,active:false,url:'https://other.test/private'}]});
  h.advance(250); h.input();
  const frame={...h.webSender(1,2),url:'https://editor.test/embed'};
  assert.equal((await h.send({type:'ACTIVITY'},frame)).ok,true);
  h.advance(50); h.input(); await h.flush();
  assert.deepEqual(h.rules().sessionRules.map(r=>r.condition.requestDomains[0]),['example.com']);
  assert.equal(h.tabMap.get(1).url,'https://example.com/edit');
  assert.ok(h.tabMap.get(2).url.startsWith(base));
  h.advance(250);h.input();await h.flush();
  assert.equal(h.rules().sessionRules.length,0);
});
test('background tabs and unfocused Chrome windows cannot extend a website grant', async () => {
  for(const focused of [false,true]) {
    const h=await harness();await h.send({type:'UNLOCK'});
    if(focused)h.tabMap.get(1).active=false;else h.focusWindow(2);
    h.advance(250);h.input();await h.send({type:'ACTIVITY'},h.webSender());
    h.advance(50);h.input();await h.flush();
    assert.equal(h.rules().sessionRules.length,0);
  }
});
test('returning before expiration renews the selected site, but returning late never revives it', async () => {
  for(const elapsed of [250,301]) {
    const h=await harness();await h.send({type:'UNLOCK'});
    h.advance(elapsed,false,false);h.input();
    h.api.tabs.onActivated.fire({tabId:1});await h.flush();
    if(elapsed===250) { h.advance(50);h.input();await h.flush();assert.equal(h.rules().sessionRules.length,1); }
    else assert.equal(h.rules().sessionRules.length,0);
  }
});
test('worker restart keeps remaining deadlines and clock rollback revokes grants', async () => {
  const h=await harness();await h.send({type:'UNLOCK'});
  h.advance(200);h.input();
  const grants=(await h.api.storage.session.get({})).grants;
  const restarted=await harness({grants,tabs:[...h.tabMap.values()],startTime:h.now()});
  restarted.advance(100);restarted.input();await restarted.flush();
  assert.equal(restarted.rules().sessionRules.length,0);
  const rollback=await harness({grants,startTime:1});
  assert.equal(rollback.rules().sessionRules.length,0);
});
test('if Chrome cannot schedule expiration, no website is left unlocked', async () => {
  const h=await harness();h.api.alarms.create=async()=>{throw Error('Alarm failed');};
  assert.equal((await h.send({type:'UNLOCK'})).ok,false);
  assert.equal(h.rules().sessionRules.length,0);
  assert.ok(h.tabMap.get(1).url.startsWith(base));
});

test('selecting a stale lock page renews a live domain session without another fingerprint', async () => {
 const url=`${base}locked.html#https://example.com/other`;
 const h=await harness({grants:[{domain:'example.com'}],tabs:[{id:1,windowId:1,active:true,url}]});
 h.advance(250);h.input();h.api.tabs.onActivated.fire({tabId:1});await h.flush();
 h.advance(50);h.input();await h.flush();assert.equal(h.rules().sessionRules.length,1);
});
test('legacy grants with no timestamp cannot become unlimited sessions', async () => {
 const h=await harness({grants:[{domain:'example.com',lastActivity:undefined}]});
 assert.equal(h.rules().sessionRules.length,0);
});

test('a newer locally installed extension reports reload needed without a GitHub request', async t => {
  t.mock.method(globalThis,'fetch',async url=>{assert.equal(url,base+'installation.json');return {ok:true,json:async()=>({managed:true})};});
  const h = await harness({native: async (_, m) => {
    assert.equal(m.operation, 'status');
    assert.equal(m.extensionVersion, h.api.runtime.getManifest().version);
    return {id:m.id, extensionManaged:true, runningExtensionManaged:m.extensionManaged, installedExtensionVersion:'0.2.0'};
  }});
  const state = await h.send({type:'LOCAL_UPDATE_STATUS'},h.sender('popup.html'));
  assert.equal(state.reloadRequired,true);
  assert.equal(state.installedVersion,'0.2.0');
  assert.equal(h.api.action.text,'↻');
  const update = await h.send({type:'UPDATE_STATUS'},h.sender('popup.html'));
  assert.equal(update.reloadRequired,true); assert.equal(update.available,false);
  assert.ok(h.tabMap.get(1).url.startsWith(base), 'Checking versions must not navigate a protected tab');
});

test('equal, older, malformed and unmanaged installation versions do not request reload', async () => {
  for (const [version,managed] of [['0.1.13',true],['0.1.1',true],['invalid',true],['0.2.0',false]]) {
    const h = await harness({native:async (_,m)=>({id:m.id, extensionManaged:managed,runningExtensionManaged:true,installedExtensionVersion:version})});
    h.api.action.text='↻';
    assert.equal((await h.send({type:'LOCAL_UPDATE_STATUS'},h.sender('settings.html'))).reloadRequired,false);
    assert.equal(h.api.action.text,'');
  }
});

test('extension settings opens a new selected tab and web pages cannot invoke it', async () => {
  const h = await harness(); const original = copy(h.tabMap.get(1));
  assert.equal((await h.send({type:'OPEN_EXTENSION_SETTINGS'},h.sender('locked.html'))).ok,true);
  const added=[...h.tabMap.values()].find(t=>t.id!==1);
  assert.equal(added.url,`chrome://extensions/?id=${ID}`); assert.equal(added.active,true);
  assert.deepEqual(h.tabMap.get(1),original);
  assert.equal((await h.send({type:'OPEN_EXTENSION_SETTINGS'},{...h.webSender(),url:'https://example.com/'})).ok,false);
  assert.equal((await h.send({type:'LOCAL_UPDATE_STATUS'},{...h.webSender(),url:'https://example.com/'})).ok,false);
});

test('the periodic installation check sets a reload badge without unlocking or reloading', async t => {
  t.mock.method(globalThis,'fetch',async()=>({ok:true,json:async()=>({managed:true})}));
  const h = await harness({native:async (_,m)=>({id:m.id,extensionManaged:true,runningExtensionManaged:m.extensionManaged,installedExtensionVersion:'0.2.0'})});
  h.api.alarms.onAlarm.fire({name:'openlocker-installation-check'}); await h.flush();
  assert.equal(h.api.action.text,'↻');
  assert.equal(h.rules().sessionRules.length,0);
});

test('a source-loaded extension does not claim that reloading activates managed files', async t => {
  t.mock.method(globalThis,'fetch',async()=>({ok:false}));
  const h=await harness({native:async(_,m)=>({id:m.id,extensionManaged:true,runningExtensionManaged:m.extensionManaged,installedExtensionVersion:'0.2.0'})});
  assert.equal((await h.send({type:'LOCAL_UPDATE_STATUS'},h.sender('popup.html'))).reloadRequired,false);
});
