import { updateStatus } from './updates.js';
import { loadProtectedSites, saveProtectedSites } from './protected-sites.js';
import { LockedTabs } from './locked-tabs.js';
import { HOST, MAX_DOMAINS, IDLE_SECONDS, normalizeDomain, protectedDomain, domainRules, grantRule, lockedURL, originalURL, trustedPage, webURL, matches } from './core.js';

const base = chrome.runtime.getURL('');
const lockedTabs = new LockedTabs(chrome, base);
let tail = Promise.resolve();
let generation = 0;
let authenticating = false;
let pendingUnlock = null;
let installingUpdate = false;
const serial = task => {
  const result = tail.then(task);
  tail = result.catch(error => console.error('OpenLocker:', error.message));
  return result;
};
const local = () => chrome.storage.local.get({ domains: [] });
const session = () => chrome.storage.session.get({ grants: [] });
const fail = message => { throw new Error(message); };
const allows = (url, grants) => !!webURL(url) && grants.some(g => matches(webURL(url).hostname, g.domain));
const activityState = () => chrome.idle.queryState(IDLE_SECONDS).catch(() => 'idle');
chrome.idle.setDetectionInterval(IDLE_SECONDS);

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
  // Save destinations before replacing pages, including abrupt manual reloads.
  const locking = new Set(tabs.filter(tab => {
    const url = tab.pendingUrl || tab.url;
    return protectedDomain(url, domains) && !allows(url, grants);
  }).map(tab => tab.id));
  await lockedTabs.remember(domains, tabs, locking);
  await Promise.all(tabs.map(async tab => {
    const url = tab.pendingUrl || tab.url;
    const domain = protectedDomain(url, domains);
    if (!domain || allows(url, grants)) return;
    try { await chrome.tabs.update(tab.id, { url: lockedURL(base, url) }); } catch { /* Tab may have closed. */ }
  }));
}

async function revoke() {
  generation++;
  await setGrants([]);
  const { domains } = await local();
  await shieldTabs(domains);
}

async function expireIfInactive() {
  const inactive = await activityState() !== 'active';
  if (inactive) await revoke();
  return inactive;
}

// Dynamic rules survive restarts. Session allow rules never survive a browser restart.
const ready = serial(async () => {
  await chrome.storage.local.setAccessLevel({ accessLevel: 'TRUSTED_CONTEXTS' });
  await chrome.storage.session.setAccessLevel({ accessLevel: 'TRUSTED_CONTEXTS' });
  const domains = await loadProtectedSites(chrome);
  const { grants } = await session();
  // A worker suspension is not a browser restart. Preserve domain sessions
  // while the user is active, including background tabs and other windows.
  // Old per-tab grants are intentionally not migrated into broader grants.
  const active = await activityState() === 'active';
  const keep = active ? grants.filter(g => g.tabId === undefined && domains.includes(g.domain)) : [];
  await syncDomains(domains);
  await setGrants(keep);
  const { recoveryReady } = await chrome.storage.session.get({ recoveryReady: false });
  // Ordinary worker suspension must not resurrect a tab the user just closed.
  if (!recoveryReady) await lockedTabs.restore(domains);
  await chrome.storage.session.set({ recoveryReady: true });
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
  await expireIfInactive();
  const { domains } = await local();
  const { grants } = await session();
  await lockedTabs.remember(domains);
  let tab;
  if (Number.isInteger(tabId)) { try { tab = await chrome.tabs.get(tabId); } catch {} }
  const url = originalURL(tab?.pendingUrl || tab?.url, base);
  const domain = protectedDomain(url, domains);
  const title = await lockedTabs.title(tabId, url);
  return { domains, url, domain, title, unlocked: allows(url, grants), updating: installingUpdate, extensionId: chrome.runtime.id };
}

async function handle(message, sender) {
  await ready;
  if (sender.id !== chrome.runtime.id) fail('Unknown sender.');
  const type = message?.type;
  // Web pages can only ask whether their own top-level document should be covered.
  if (type === 'GUARD') {
    if (!sender.tab || sender.frameId !== 0 || !webURL(sender.url)) fail('Invalid page.');
    return serial(async () => {
      await expireIfInactive();
      const { domains } = await local();
      const { grants } = await session();
      const domain = protectedDomain(sender.url, domains);
      const allowed = !domain || allows(sender.url, grants);
      return { allowed, redirect: allowed ? null : lockedURL(base, sender.url) };
    });
  }
  if (!trustedPage(sender, base, ['popup.html', 'locked.html', 'settings.html'])) fail('This action is only available inside OpenLocker.');
  if (type === 'STATUS') return serial(() => snapshot(sender.tab?.id ?? message.tabId));
  if (installingUpdate && ['UNLOCK', 'LOCK_DOMAIN', 'REMOVE_DOMAIN', 'INSTALL_UPDATE'].includes(type)) fail('OpenLocker is updating. Your sites and tabs are being preserved.');
  if (type === 'HELPER_STATUS') {
    try { return await native('status'); } catch (error) { return { available: false, message: error.message }; }
  }
  if (type === 'UPDATE_STATUS' || type === 'INSTALL_UPDATE') {
    if (!trustedPage(sender, base, ['popup.html', 'settings.html'])) fail('Updates are only available in OpenLocker settings or its popup.');
    if (type === 'UPDATE_STATUS') return updateStatus(message.force === true);
    installingUpdate = true;
    try {
      const update = await updateStatus(true);
      if (!update.managed) fail('This copy was loaded from a development folder. Install the latest Mac installer, then load the extension folder shown by it once. Future updates use this button.');
      if (!update.available) return { updated: false };
      const helper = await native('status');
      if (!helper.supportsUpdates) fail('Install OpenLocker 0.1.2 or newer once to enable one-click updates.');
      await serial(() => revoke());
      const result = await native('update-extension');
      if (result.success !== true) fail(result.message || 'The update failed. Your sites remain locked.');
      await serial(async () => {
        const { domains } = await local();
        await saveProtectedSites(chrome, domains);
        await lockedTabs.prepareReload(domains);
      });
      return { updated: true, version: result.version };
    } finally { installingUpdate = false; }
  }
  if (type === 'LOCK_DOMAIN') return serial(async () => {
    const domain = normalizeDomain(message.domain);
    const { domains } = await local();
    if (domains.includes(domain)) { await revoke(); return {}; }
    if (domains.length >= MAX_DOMAINS) fail(`You can protect up to ${MAX_DOMAINS} domains.`);
    const next = [...domains, domain].sort();
    // Persist intent first; if rule installation fails, restore the previous state.
    await saveProtectedSites(chrome, next);
    try { await syncDomains(next); } catch (error) { await saveProtectedSites(chrome, domains); throw error; }
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
    // A lock page in another tab may predate this domain's authentication.
    // Restore it without requesting another fingerprint during the idle session.
    const restored = await serial(async () => {
      if (await expireIfInactive()) fail('Your Mac is idle or locked. Return to this tab to unlock it.');
      const { grants } = await session();
      if (!allows(url, grants)) return false;
      const current = await chrome.tabs.get(sender.tab.id);
      if (current.url !== sender.url) fail('The tab changed. Try again.');
      await chrome.tabs.update(sender.tab.id, { url });
      return true;
    });
    if (restored) return {};
    if (pendingUnlock) fail('A Touch ID request is already open.');
    const attempt = { tabId: sender.tab.id, url: sender.url, generation };
    pendingUnlock = attempt;
    try {
    await authenticate(domain);
    return await serial(async () => {
      if (await expireIfInactive()) fail('Your Mac became idle or locked. Try unlocking again.');
      const current = await chrome.tabs.get(sender.tab.id);
      if (generation !== attempt.generation || current.url !== sender.url || !current.active) fail('The tab changed. Try unlocking again.');
      const latest = await local();
      if (protectedDomain(url, latest.domains) !== domain) fail('The domain settings changed. Try again.');
      const { grants } = await session();
      await setGrants([...grants.filter(g => g.domain !== domain), { domain }]);
      try { await chrome.tabs.update(sender.tab.id, { url }); }
      catch (error) { await setGrants(grants); throw error; }
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
      await saveProtectedSites(chrome, next);
      try { await syncDomains(next); } catch (error) { await saveProtectedSites(chrome, domains); throw error; }
      await revoke();
      return {};
    });
  }
  fail('Unknown action.');
}

chrome.runtime.onMessage.addListener((message, sender, respond) => {
  const runtime = chrome.runtime;
  const reply = data => { try { respond(data); } catch { /* The popup may have closed during the download. */ } };
  handle(message, sender).then(data => {
    reply({ ok: true, ...data });
    // The worker owns the handoff: closing the initiating popup must not strand
    // parked tabs or leave new files waiting indefinitely for a manual reload.
    if (message.type === 'INSTALL_UPDATE' && data.updated) runtime.reload();
  }, error => reply({ ok: false, error: error.message }));
  return true;
});
const event = task => { serial(async () => { await ready; await task(); }).catch(() => {}); };
// Switching is activity, not a reason to revoke an authenticated session.
// It still invalidates a fingerprint request for a tab the user left.
chrome.tabs.onActivated.addListener(({ tabId }) => {
  if (pendingUnlock && pendingUnlock.tabId !== tabId) generation++;
  event(async () => lockedTabs.remember((await local()).domains));
});
chrome.windows.onFocusChanged.addListener(windowId => {
  if (windowId !== chrome.windows.WINDOW_ID_NONE) event(async () => {
    const [tab] = await chrome.tabs.query({ active: true, windowId });
    if (pendingUnlock && pendingUnlock.tabId !== tab?.id) generation++;
  });
});
chrome.tabs.onRemoved.addListener((tabId, info) => {
  if (pendingUnlock?.tabId === tabId) generation++;
  event(() => lockedTabs.forget(tabId, info));
});
for (const changed of [chrome.tabs.onMoved, chrome.tabs.onAttached, chrome.tabs.onDetached]) {
  changed.addListener(() => event(async () => lockedTabs.remember((await local()).domains)));
}
chrome.tabs.onUpdated.addListener((tabId, change) => {
  if (!change.url) {
    if ('pinned' in change || 'title' in change || change.status === 'complete') {
      event(async () => lockedTabs.remember((await local()).domains));
    }
    return;
  }
  if (pendingUnlock?.tabId === tabId && change.url !== pendingUnlock.url) generation++;
  event(async () => {
    const { grants } = await session();
    const { domains } = await local();
    await shieldTabs(domains, grants);
  });
});
chrome.webNavigation.onCommitted.addListener(details => {
  if (details.frameId === 0) event(async () => {
    const { domains } = await local();
    const { grants } = await session();
    await shieldTabs(domains, grants);
  });
});
chrome.idle.onStateChanged.addListener(state => { if (state !== 'active') event(() => revoke()); });
chrome.runtime.onStartup.addListener(() => event(() => revoke()));
chrome.runtime.onInstalled.addListener(details => event(async () => {
  await revoke();
  if (details.reason === 'install') await chrome.runtime.openOptionsPage();
}));
