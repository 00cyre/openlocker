import { $, request } from './ui.js';
let checking = false;
async function refresh() {
  if (checking || document.visibilityState === 'hidden') return;
  checking = true;
  try {
    const state = await request('LOCAL_UPDATE_STATUS');
    $('#reload-notice').hidden = !state.reloadRequired;
    $('#reload-description').textContent = state.reloadRequired
      ? `Version ${state.installedVersion} is installed; Chrome is running ${state.runningVersion}. Click Reload in extension settings, then refresh open webpages when ready.` : '';
  } catch { /* Local update notices must not interfere with locking. */ }
  finally { checking = false; }
}
$('#extension-settings').addEventListener('click', () => {
  request('OPEN_EXTENSION_SETTINGS').catch(() => {});
});
addEventListener('focus', refresh);
document.addEventListener('visibilitychange', refresh);
setInterval(refresh, 60_000);
void refresh();
