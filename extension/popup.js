import { $, request, busy } from './ui.js';
import { normalizeDomain, lockedURL } from './core.js';
let tab;
let state;
let helper;
async function render() {
  [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
  [state, helper] = await Promise.all([request('STATUS', { tabId: tab?.id }), request('HELPER_STATUS')]);
  $('#count').textContent = `${state.domains.length} protected ${state.domains.length === 1 ? 'site' : 'sites'}`;
  if (!state.url) {
    $('#domain').textContent = 'Make it private.';
    $('#site-description').textContent = 'Open a website to protect it with Touch ID.';
    $('#action').textContent = 'Manage protected sites';
    $('#hint').textContent = 'Chrome pages and the Web Store cannot be locked.';
  } else {
    $('#domain').textContent = state.domain || normalizeDomain(state.url);
    $('#site-label').textContent = state.domain ? (state.unlocked ? 'Unlocked for now' : 'Protected website') : 'Current website';
    $('#site-description').textContent = state.domain ? 'This domain and its subdomains are protected.' : 'Lock this domain and its subdomains.';
    $('#action').textContent = !helper.available ? 'Set up Touch ID' : state.unlocked ? 'Lock this site now' : state.domain ? 'Open locked tab' : 'Lock this site';
    $('#hint').textContent = state.unlocked ? 'Relocks after 5 minutes without using this site.' : 'Touch ID once. Stays open while you use this site.';
  }
  $('#action').disabled = false;
}
$('#settings').addEventListener('click', () => chrome.runtime.openOptionsPage());
$('#action').addEventListener('click', () => busy($('#action'), async () => {
  if (!state?.url || !helper?.available) { await chrome.runtime.openOptionsPage(); return; }
  if (state.domain && !state.unlocked) await chrome.tabs.update(tab.id, { url: lockedURL(chrome.runtime.getURL(''), state.url) });
  else if (state.unlocked) await request('LOCK_ALL');
  else await request('LOCK_DOMAIN', { domain: normalizeDomain(state.url) });
  window.close();
}));
$('#lock-all').addEventListener('click', () => busy($('#lock-all'), async () => { await request('LOCK_ALL'); window.close(); }));
render().catch(error => { $('#domain').textContent = 'Could not connect'; $('#site-description').textContent = error.message; });
