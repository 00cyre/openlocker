import { updateStatus } from './updates.js';
import { HOST, MAX_DOMAINS, normalizeDomain, protectedDomain, domainRules, grantRule, lockedURL, originalURL, trustedPage, webURL, matches } from './core.js';

const base = chrome.runtime.getURL('');
let tail = Promise.resolve();
let generation = 0;
let authenticating = false;
let pendingUnlock = null;
const serial = task => {
  const result = tail.then(task);
  tail = result.catch(error => console.error('OpenLocker:', error.message));
  return result;
};
const local = () => chrome.storage.local.get({ domains: [] });
const session = () => chrome.storage.session.get({ grants: [] });
const fail = message => { throw new Error(message); };

async function syncDomains(domains) {
  const current = await chrome.declarativeNetRequest.getDynamicRules();
  await chrome.declarativeNetRequest.updateDynamicRules({ removeRuleIds: current.map(r => r.id), addRules: domainRules(domains, base) });
}

async function setGrants(grants) {
  const current = await chrome.declarativeNetRequest.getSessionRules();
  await chrome.declarativeNetRequest.updateSessionRules({ removeRuleIds: current.map(r => r.id), addRules: grants.map(grantRule) });
  await chrome.storage.session.set({ grants });
}

async function shieldTabs(domains, grants = []) {
  const tabs = await chrome.tabs.query({});
  await Promise.all(tabs.map(async tab => {
    const url = tab.pendingUrl || tab.url;
    const domain = protectedDomain(url, domains);
    if (!domain || grants.some(g => g.tabId === tab.id && matches(webURL(url).hostname, g.domain))) return;
    try { await chrome.tabs.update(tab.id, { url: lockedURL(base, url) }); } catch { /* Tab may have closed. */ }
  }));
}

async function revoke(exceptTabId = null) {
  // Returning from the system Touch ID sheet to the same tab is not a tab switch.
  if (exceptTabId === null || pendingUnlock?.tabId !== exceptTabId) generation++;
  const { grants } = await session();
  const keep = grants.filter(g => g.tabId === exceptTabId);
  await setGrants(keep);
  const { domains } = await local();
  await shieldTabs(domains, keep);
}

// Dynamic rules survive restarts. Session allow rules never survive a browser restart.
const ready = serial(async () => {
  await chrome.storage.local.setAccessLevel({ accessLevel: 'TRUSTED_CONTEXTS' });
  await chrome.storage.session.setAccessLevel({ accessLevel: 'TRUSTED_CONTEXTS' });
  const { domains } = await local();
  const { grants } = await session();
  const tabs = await chrome.tabs.query({ active: true });
  const keep = grants.filter(g => tabs.some(t => t.id === g.tabId && protectedDomain(originalURL(t.pendingUrl || t.url, base), domains) === g.domain));
  await syncDomains(domains);
  await setGrants(keep);
  await shieldTabs(domains, keep);
});

async function native(operation, domain = '') {
  const id = crypto.randomUUID();
  let response;
  try { response = await chrome.runtime.sendNativeMessage(HOST, { operation, id, domain }); }
  catch { fail('Install the OpenLocker Mac helper, then try again.'); }
  if (response?.id !== id) fail('The Mac helper returned an invalid response.');
  return response;
}

async function authenticate(domain) {
  if (authenticating) fail('A Touch ID request is already open.');
  authenticating = true;
  try {
    const response = await native('authenticate', domain);
    if (response.success !== true) fail(response.message || 'Touch ID did not unlock this site. Try again.');
  } finally { authenticating = false; }
}

async function snapshot(tabId) {
  const { domains } = await local();
  const { grants } = await session();
  let tab;
  if (Number.isInteger(tabId)) { try { tab = await chrome.tabs.get(tabId); } catch {} }
  const url = originalURL(tab?.pendingUrl || tab?.url, base);
  const domain = protectedDomain(url, domains);
  return { domains, url, domain, unlocked: !!url && grants.some(g => g.tabId === tabId && matches(webURL(url).hostname, g.domain)), extensionId: chrome.runtime.id };
}

async function handle(message, sender) {
  await ready;
  if (sender.id !== chrome.runtime.id) fail('Unknown sender.');
  const type = message?.type;
  // Web pages can only ask whether their own top-level document should be covered.
  if (type === 'GUARD') {
    if (!sender.tab || sender.frameId !== 0 || !webURL(sender.url)) fail('Invalid page.');
    return serial(async () => {
      const { domains } = await local();
      const { grants } = await session();
      const domain = protectedDomain(sender.url, domains);
      const allowed = !domain || grants.some(g => g.tabId === sender.tab.id && matches(webURL(sender.url).hostname, g.domain));
      return { allowed, redirect: allowed ? null : lockedURL(base, sender.url) };
    });
  }
  if (!trustedPage(sender, base, ['popup.html', 'locked.html', 'settings.html'])) fail('This action is only available inside OpenLocker.');
  if (type === 'STATUS') return serial(() => snapshot(sender.tab?.id ?? message.tabId));
  if (type === 'HELPER_STATUS') {
    try { return await native('status'); } catch (error) { return { available: false, message: error.message }; }
  }
  if (type === 'UPDATE_STATUS' || type === 'INSTALL_UPDATE') {
    if (!trustedPage(sender, base, ['popup.html', 'settings.html'])) fail('Updates are only available in OpenLocker settings or its popup.');
    if (type === 'UPDATE_STATUS') return updateStatus(message.force === true);
    const update = await updateStatus(true);
    if (!update.managed) fail('This copy was loaded from a development folder. Install the latest Mac installer, then load the extension folder shown by it once. Future updates use this button.');
    if (!update.available) return { updated: false };
    const helper = await native('status');
    if (!helper.supportsUpdates) fail('Install OpenLocker 0.1.2 or newer once to enable one-click updates.');
    await serial(() => revoke());
    const result = await native('update-extension');
    if (result.success !== true) fail(result.message || 'The update failed. Your sites remain locked.');
    return { updated: true, version: result.version };
  }
  if (type === 'LOCK_DOMAIN') return serial(async () => {
    const domain = normalizeDomain(message.domain);
    const { domains } = await local();
    if (domains.includes(domain)) { await revoke(); return {}; }
    if (domains.length >= MAX_DOMAINS) fail(`You can protect up to ${MAX_DOMAINS} domains.`);
    const next = [...domains, domain].sort();
    // Persist intent first; if rule installation fails, restore the previous state.
    await chrome.storage.local.set({ domains: next });
    try { await syncDomains(next); } catch (error) { await chrome.storage.local.set({ domains }); throw error; }
    await revoke();
    return {};
  });
  if (type === 'LOCK_ALL') return serial(async () => { await revoke(); return {}; });
  if (type === 'UNLOCK') {
    if (!trustedPage(sender, base, ['locked.html']) || !sender.tab) fail('Open the locked tab to use Touch ID.');
    const url = originalURL(sender.url, base);
    const { domains } = await local();
    const domain = protectedDomain(url, domains);
    if (!domain) fail('This site is no longer protected.');
    if (pendingUnlock) fail('A Touch ID request is already open.');
    const attempt = { tabId: sender.tab.id, url: sender.url, generation };
    pendingUnlock = attempt;
    try {
    await authenticate(domain);
    return await serial(async () => {
      const current = await chrome.tabs.get(sender.tab.id);
      if (generation !== attempt.generation || current.url !== sender.url || !current.active) fail('The tab changed. Try unlocking again.');
      const latest = await local();
      if (protectedDomain(url, latest.domains) !== domain) fail('The domain settings changed. Try again.');
      const { grants } = await session();
      await setGrants([...grants.filter(g => g.tabId !== sender.tab.id), { tabId: sender.tab.id, domain }]);
      try { await chrome.tabs.update(sender.tab.id, { url }); }
      catch (error) { await setGrants(grants.filter(g => g.tabId !== sender.tab.id)); throw error; }
      return {};
    });
    } finally { if (pendingUnlock === attempt) pendingUnlock = null; }
  }
  if (type === 'REMOVE_DOMAIN') {
    if (!trustedPage(sender, base, ['settings.html'])) fail('Manage protected sites in settings.');
    const domain = normalizeDomain(message.domain);
    await authenticate(domain);
    return serial(async () => {
      const { domains } = await local();
      const next = domains.filter(d => d !== domain);
      await syncDomains(next);
      await chrome.storage.local.set({ domains: next });
      await revoke();
      return {};
    });
  }
  fail('Unknown action.');
}

chrome.runtime.onMessage.addListener((message, sender, respond) => {
  handle(message, sender).then(data => respond({ ok: true, ...data }), error => respond({ ok: false, error: error.message }));
  return true;
});
const event = task => { serial(async () => { await ready; await task(); }).catch(() => {}); };
chrome.tabs.onActivated.addListener(({ tabId }) => event(() => revoke(tabId)));
chrome.windows.onFocusChanged.addListener(windowId => {
  if (windowId !== chrome.windows.WINDOW_ID_NONE) event(async () => {
    const [tab] = await chrome.tabs.query({ active: true, windowId });
    await revoke(tab?.id);
  });
});
chrome.tabs.onRemoved.addListener(tabId => event(async () => {
  const { grants } = await session();
  await setGrants(grants.filter(g => g.tabId !== tabId));
}));
chrome.tabs.onUpdated.addListener((tabId, change) => {
  if (!change.url) return;
  if (pendingUnlock?.tabId === tabId && change.url !== pendingUnlock.url) generation++;
  event(async () => {
    const { grants } = await session();
    const keep = grants.filter(g => g.tabId !== tabId || (webURL(change.url) && matches(webURL(change.url).hostname, g.domain)));
    if (keep.length !== grants.length) { generation++; await setGrants(keep); }
    const { domains } = await local();
    await shieldTabs(domains, keep);
  });
});
chrome.webNavigation.onCommitted.addListener(details => {
  if (details.frameId === 0) event(async () => {
    const { domains } = await local();
    const { grants } = await session();
    await shieldTabs(domains, grants);
  });
});
chrome.idle.onStateChanged.addListener(state => { if (state === 'locked') event(() => revoke()); });
chrome.runtime.onStartup.addListener(() => event(() => revoke()));
chrome.runtime.onInstalled.addListener(details => event(async () => {
  await revoke();
  if (details.reason === 'install') await chrome.runtime.openOptionsPage();
}));
