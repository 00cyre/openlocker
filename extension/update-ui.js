import { $, request, notice } from './ui.js';
let info;
let pending = false;
const button = $('#update');
const label = $('#update-status');
function render() {
  button.textContent = info?.reloadRequired ? 'Open extension settings ↗' : info?.available ? `Update to ${info.version}` : 'Check for updates';
  label.textContent = info?.reloadRequired ? `${info.version} installed · reload needed` : info?.available ? 'Update available' : `Version ${info.installed} · up to date`;
}
async function check(force = false) {
  info = await request('UPDATE_STATUS', { force });
  render();
}
button.addEventListener('click', async () => {
  if (pending) return;
  pending = true; button.disabled = true; notice('');
  try {
    if (info?.reloadRequired) { await request('OPEN_EXTENSION_SETTINGS'); return; }
    if (!info?.available) await check(true);
    if (info?.reloadRequired) { await request('OPEN_EXTENSION_SETTINGS'); return; }
    if (info?.available) {
      button.textContent = 'Updating…';
      const result = await request('INSTALL_UPDATE');
      if (result.updated) return;
      await check(true);
    }
  } catch (error) { notice(error.message, true); }
  finally { pending = false; button.disabled = false; if (info) render(); else button.textContent = 'Check for updates'; }
});
check().catch(() => { label.textContent = `Version ${chrome.runtime.getManifest().version}`; button.textContent = 'Check for updates'; });
