import { lockedURL, originalURL, protectedDomain, webURL } from './core.js';

// Chrome closes extension-origin tabs during both manual and runtime.reload().
// Keep a profile-local journal throughout normal use, not just during updates.
// It holds destinations/window placement, never authentication grants.
export class LockedTabs {
  constructor(api, base) { this.api = api; this.base = base; this.parking = false; this.pending = []; }
  isLockPage(url) { return url?.startsWith(`${this.base}locked.html#`) && !!originalURL(url, this.base); }
  async entries() {
    const { lockedTabs = [] } = await this.api.storage.local.get({ lockedTabs: [] });
    if (!Array.isArray(lockedTabs)) throw Error('The saved locked tabs need attention. Reload was stopped.');
    return lockedTabs.filter(row => Number.isInteger(row?.id) && Number.isInteger(row.windowId) && webURL(row.url));
  }
  async remember(domains, tabs = null) {
    if (this.parking) return;
    tabs ??= await this.api.tabs.query({});
    const rows = tabs.filter(tab => this.isLockPage(tab.pendingUrl || tab.url)).map(tab => ({
      id: tab.id, url: originalURL(tab.pendingUrl || tab.url, this.base), windowId: tab.windowId,
      index: tab.index ?? 0, pinned: tab.pinned === true, active: tab.active === true
    })).filter(row => protectedDomain(row.url, domains));
    for (const row of this.pending) if (!rows.some(current => current.id === row.id)) rows.push(row);
    const before = await this.entries();
    if (JSON.stringify(before) !== JSON.stringify(rows)) await this.api.storage.local.set({ lockedTabs: rows });
  }
  async forget(tabId, info = {}) {
    if (this.parking) return;
    const keep = row => row.id !== tabId && !(info.isWindowClosing && row.windowId === info.windowId);
    this.pending = this.pending.filter(keep);
    await this.api.storage.local.set({ lockedTabs: (await this.entries()).filter(keep) });
  }
  async restore(domains) {
    const saved = (await this.entries()).filter(row => protectedDomain(row.url, domains));
    const live = await this.api.tabs.query({});
    const used = new Set();
    const windows = new Map(live.map(tab => [tab.windowId, tab.windowId]));
    this.pending = [];
    for (const row of saved.sort((a, b) => a.windowId - b.windowId || a.index - b.index)) {
      const url = lockedURL(this.base, row.url);
      const original = live.find(tab => tab.id === row.id);
      try {
        // A surviving tab ID may have navigated elsewhere. Never overwrite it.
        if (original && !used.has(original.id)) {
          if (row.parked && original.url === row.parked) await this.api.tabs.update(original.id, { url });
          used.add(original.id);
          continue;
        }
        // Browser session restore can change IDs. Match each occurrence once so
        // duplicate URLs stay duplicated, without creating extra restored tabs.
        const restored = live.find(tab => !used.has(tab.id) && (tab.url === url || tab.pendingUrl === url) &&
          (!windows.has(row.windowId) || tab.windowId === windows.get(row.windowId)));
        if (restored) { used.add(restored.id); continue; }
        let tab;
        if (windows.has(row.windowId)) {
          tab = await this.api.tabs.create({ url, windowId: windows.get(row.windowId),
            index: row.index, pinned: row.pinned, active: row.active });
        } else {
          // A window containing only extension pages may have closed as well.
          const window = await this.api.windows.create({ url, focused: false });
          windows.set(row.windowId, window.id);
          tab = window.tabs?.[0] || (await this.api.tabs.query({ windowId: window.id }))[0];
          if (!tab) throw Error('The restored window has no tab.');
          if (row.pinned) await this.api.tabs.update(tab.id, { pinned: true });
        }
        used.add(tab.id);
        // Commit each new ID before continuing so another worker restart cannot
        // replay a successfully restored tab. Keep failures for a later retry.
        row.id = tab.id; row.windowId = tab.windowId; delete row.parked;
        await this.api.storage.local.set({ lockedTabs: saved });
      } catch { this.pending.push(row); }
    }
    await this.remember(domains);
  }
  async prepareReload(domains) {
    await this.remember(domains);
    const rows = await this.entries();
    this.parking = true;
    try {
      for (const row of rows) {
        row.parked = `about:blank#openlocker-${crypto.randomUUID()}`;
        await this.api.storage.local.set({ lockedTabs: rows });
        await this.api.tabs.update(row.id, { url: row.parked });
        let parked = false;
        for (let attempt = 0; attempt < 100; attempt++) {
          const tab = await this.api.tabs.get(row.id);
          if (tab.url === row.parked && tab.status !== 'loading' && (!tab.pendingUrl || tab.pendingUrl === row.parked)) { parked = true; break; }
          await new Promise(resolve => setTimeout(resolve, 50));
        }
        if (!parked) throw Error('Chrome could not safely preserve a locked tab. Try updating again.');
      }
    } catch (error) {
      this.parking = false;
      // Roll back only tabs that still exist. A user closing a tab during the
      // update must not cause that tab to be resurrected by error recovery.
      for (const row of rows) {
        const tab = await this.api.tabs.get(row.id).catch(() => null);
        if (tab && row.parked && [tab.url, tab.pendingUrl].includes(row.parked)) {
          try { await this.api.tabs.update(row.id, { url: lockedURL(this.base, row.url) }); }
          catch { this.pending.push(row); }
        }
      }
      await this.remember(domains);
      throw error;
    }
  }
}
