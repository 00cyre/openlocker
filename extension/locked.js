import { $, request, busy, notice } from './ui.js';
import { webURL } from './core.js';
const target = webURL(location.hash.slice(1));
let unlocking = false;
let wheelTimer;

function identity(state = {}) {
  if (!target) return;
  document.title = `${state.title || `${target.host}${target.pathname === '/' ? '' : target.pathname}`} · Locked`;
  // Chrome serves its stored favicon from our own extension origin. Loading a
  // lock page never needs to request the protected website's favicon directly.
  const icon = new URL(chrome.runtime.getURL('_favicon/'));
  icon.searchParams.set('pageUrl', target.href);
  icon.searchParams.set('size', '32');
  $('#site-icon').href = icon.href;
}
async function render() {
  if (!target) { $('#description').textContent = 'Open a protected website to unlock it.'; return; }
  $('#domain').textContent = target.host;
  const state = await request('STATUS');
  identity(state);
  $('#unlock').textContent = state.domain ? 'Unlock with Touch ID' : 'Continue to website';
  if (!state.domain) $('#description').textContent = 'This website is no longer on your protected list.';
  $('#unlock').disabled = false;
  // A sibling tab may have unlocked this domain already. Resume that existing
  // session without opening Touch ID; focus alone never starts authentication.
  if (state.unlocked && !state.updating && document.visibilityState === 'visible' && document.hasFocus()) {
    location.replace(target.href);
  }
}
async function unlock() {
  if (!target || unlocking || document.visibilityState !== 'visible' || !document.hasFocus()) return;
  unlocking = true;
  try {
    await busy($('#unlock'), async () => {
      const state = await request('STATUS');
      if (state.updating) return;
      if (state.domain && !state.unlocked) await request('UNLOCK');
      else location.replace(target.href);
    }, 'Waiting for your fingerprint…');
  } finally { unlocking = false; }
}
function interact(event) {
  if (!event.isTrusted || event.target?.closest?.('#settings') || event.altKey || event.ctrlKey || event.metaKey) return;
  if (event.type === 'keydown' && (event.repeat || ['Alt', 'Control', 'Meta', 'Shift', 'Tab', 'Escape', 'CapsLock'].includes(event.key))) return;
  if (event.type === 'pointerdown' && event.button !== 0) return;
  if (event.type === 'wheel') {
    // A trackpad's momentum is one gesture, even if Touch ID is cancelled.
    const continuing = wheelTimer !== undefined;
    clearTimeout(wheelTimer);
    wheelTimer = setTimeout(() => { wheelTimer = undefined; }, 300);
    if (continuing) return;
  }
  void unlock();
}
for (const type of ['pointerdown', 'keydown', 'wheel']) document.addEventListener(type, interact, { passive: true });
// The button also supports assistive technology's trusted click activation.
$('#unlock').addEventListener('click', event => { if (event.isTrusted) void unlock(); });
const refresh = () => { if (!unlocking) render().catch(error => notice(error.message, true)); };
window.addEventListener('focus', refresh);
document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible') refresh(); });
$('#settings').addEventListener('click', () => chrome.runtime.openOptionsPage());
identity();
refresh();
