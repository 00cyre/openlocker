import { $, request, busy, notice } from './ui.js';
import { webURL } from './core.js';
const target = webURL(location.hash.slice(1));
let state;
let autoAttempted = false;
let unlocking = false;
async function render() {
  if (!target) { $('#description').textContent = 'Open a protected website to unlock it.'; return; }
  $('#domain').textContent = target.hostname;
  state = await request('STATUS');
  $('#unlock').textContent = state.domain ? 'Unlock with Touch ID' : 'Continue to website';
  if (!state.domain) $('#description').textContent = 'This website is no longer on your protected list.';
  $('#unlock').disabled = false;
  maybeAutoUnlock();
}
async function unlock() {
  if (unlocking) return;
  unlocking = true;
  autoAttempted = true;
  await busy($('#unlock'), async () => {
  // Settings may have removed protection while this lock page stayed open.
  state = await request('STATUS');
  if (state.domain) await request('UNLOCK');
  else location.replace(target.href);
  }, 'Waiting for your fingerprint…');
  unlocking = false;
  maybeAutoUnlock();
}
function maybeAutoUnlock() {
  if (state?.domain && !autoAttempted && !unlocking && document.visibilityState === 'visible' && document.hasFocus()) void unlock();
}
$('#unlock').addEventListener('click', unlock);
window.addEventListener('focus', maybeAutoUnlock);
document.addEventListener('visibilitychange', () => {
  if (document.visibilityState === 'hidden') autoAttempted = false;
  else maybeAutoUnlock();
});
$('#settings').addEventListener('click', () => chrome.runtime.openOptionsPage());
render().catch(error => notice(error.message, true));
