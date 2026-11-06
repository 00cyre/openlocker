import { $, request, notice } from './ui.js';
let info;
let pending = false;
const button = $('#update');
const label = $('#update-status');
async function check(force = false) {
  info = await request('UPDATE_STATUS', { force });
  button.textContent = info.available ? `Update to ${info.version}` : 'Check for updates';
  label.textContent = info.available ? 'Update available' : `Version ${info.installed} · up to date`;
}
button.addEventListener('click', async () => {
  if (pending) return;
  pending = true; button.disabled = true; notice('');
  try {
    if (!info?.available) await check(true);
    if (info?.available) {
      button.textContent = 'Updating…';
      await request('INSTALL_UPDATE');
      chrome.runtime.reload();
      return;
    }
  } catch (error) { notice(error.message, true); }
  finally { pending = false; button.disabled = false; button.textContent = info?.available ? `Update to ${info.version}` : 'Check for updates'; }
});
check().catch(() => { label.textContent = `Version ${chrome.runtime.getManifest().version}`; button.textContent = 'Check for updates'; });
