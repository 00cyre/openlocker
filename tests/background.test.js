import test from 'node:test';
import assert from 'node:assert/strict';

const ID = 'abcdefghijklmnopabcdefghijklmnop';
const base = `chrome-extension://${ID}/`;
const event = () => { const listeners = []; return { addListener(fn) { listeners.push(fn); }, fire(...args) { for (const fn of listeners) fn(...args); }, listeners }; };
const copy = value => structuredClone(value);
// Model the documented Chrome matching defaults at the navigation boundary.
// In particular, an omitted resource-type filter EXCLUDES main_frame.
// https://developer.chrome.com/docs/extensions/reference/api/declarativeNetRequest#type-RuleCondition
function networkRule(rules, { url, type = 'main_frame', tabId }) {
  const host = new URL(url).hostname;
  return rules.filter(({ condition: c }) =>
    (!c.tabIds || c.tabIds.includes(tabId)) &&
    (!c.requestDomains || c.requestDomains.some(d => host === d || host.endsWith(`.${d}`))) &&
    (!c.regexFilter || new RegExp(c.regexFilter).test(url)) &&
    (c.resourceTypes ? c.resourceTypes.includes(type) : c.excludedResourceTypes ? !c.excludedResourceTypes.includes(type) : type !== 'main_frame')
  ).sort((a, b) => b.priority - a.priority)[0];
}
function storage(initial = {}) {
  let data = initial;
  return { async get(defaults) { return copy({ ...defaults, ...data }); }, async set(value) { Object.assign(data, copy(value)); }, async setAccessLevel() {} };
}
let counter = 0;
async function harness({ domains = ['example.com'], grants = [], tabs, native, network = false } = {}) {
  let dynamic = [];
  let sessionRules = [];
  const tabMap = new Map((tabs || [{ id: 1, active: true, url: `${base}locked.html#https://example.com/private`, windowId: 1 }]).map(t => [t.id, copy(t)]));
  const api = {
    runtime: { id: ID, getURL: path => base + path, onMessage: event(), onStartup: event(), onInstalled: event(), openOptionsPage: async () => {}, sendNativeMessage: native || (async (_, message) => ({ id: message.id, success: true, available: true })) },
    storage: { local: storage({ domains }), session: storage({ grants }) },
    declarativeNetRequest: {
      getDynamicRules: async () => copy(dynamic),
      getSessionRules: async () => copy(sessionRules),
      updateDynamicRules: async ({ addRules }) => { dynamic = copy(addRules); },
      updateSessionRules: async ({ addRules }) => { sessionRules = copy(addRules); }
    },
    tabs: {
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
      onActivated: event(), onUpdated: event(), onRemoved: event()
    },
    windows: { WINDOW_ID_NONE: -1, onFocusChanged: event() },
    webNavigation: { onCommitted: event() }, idle: { onStateChanged: event() }
  };
  globalThis.chrome = api;
  await import(`../extension/background.js?test=${counter++}`);
  const sender = (page = 'locked.html', tabId = 1) => ({ id: ID, frameId: 0, url: page === 'locked.html' ? tabMap.get(tabId).url : `${base}${page}`, tab: copy(tabMap.get(tabId)) });
  const send = (message, source = sender()) => new Promise(resolve => api.runtime.onMessage.listeners[0](message, source, resolve));
  await send({ type: 'STATUS' });
  return { api, send, sender, tabMap, rules: () => ({ dynamic, sessionRules }) };
}

test('successful native authentication unlocks one tab only', async () => {
  const h = await harness();
  const result = await h.send({ type: 'UNLOCK' });
  assert.equal(result.ok, true);
  assert.equal(h.tabMap.get(1).url, 'https://example.com/private');
  assert.deepEqual(h.rules().sessionRules[0].condition.tabIds, [1]);
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
  assert.equal(networkRule(rules, { url, tabId: 2 }).action.type, 'redirect', 'Other tabs stay locked');
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
test('tab switching revokes the grant and redirects the exposed document', async () => {
  const h = await harness();
  await h.send({ type: 'UNLOCK' });
  h.tabMap.get(1).active = false;
  h.api.tabs.onActivated.fire({ tabId: 2 });
  await h.send({ type: 'STATUS' }, h.sender('settings.html'));
  assert.equal(h.rules().sessionRules.length, 0);
  assert.ok(h.tabMap.get(1).url.startsWith(base));
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
test('service worker restart retains an active tab grant but discards a stale one', async () => {
  const h = await harness({
    grants: [{ tabId: 1, domain: 'example.com' }, { tabId: 8, domain: 'example.com' }],
    tabs: [{ id: 1, active: true, url: 'https://example.com/private', windowId: 1 }]
  });
  assert.equal(h.rules().sessionRules.length, 1);
  assert.equal(h.tabMap.get(1).url, 'https://example.com/private');
});
test('leaving a protected domain revokes the tab allowance', async () => {
  const h = await harness();
  await h.send({ type: 'UNLOCK' });
  h.tabMap.get(1).url = 'https://other.test/';
  h.api.tabs.onUpdated.fire(1, { url: 'https://other.test/' });
  await h.send({ type: 'STATUS' }, h.sender('settings.html'));
  assert.equal(h.rules().sessionRules.length, 0);
});
test('unlocking a parent domain also authorizes its protected child in that tab', async () => {
  const h = await harness({ domains: ['example.com', 'mail.example.com'] });
  await h.send({ type: 'UNLOCK' });
  h.tabMap.get(1).url = 'https://mail.example.com/inbox';
  const state = await h.send({ type: 'STATUS' }, h.sender('settings.html'));
  assert.equal(state.unlocked, true);
  assert.equal((await h.send({ type: 'GUARD' }, { id: ID, frameId: 0, url: h.tabMap.get(1).url, tab: { id: 1 } })).allowed, true);
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
