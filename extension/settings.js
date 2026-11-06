import { $, request, busy, notice } from './ui.js';
let helperAvailable = false;
async function checkHelper() {
  const helper = await request('HELPER_STATUS');
  helperAvailable = helper.available === true;
  $('#helper-status').textContent = helperAvailable ? 'Touch ID is ready' : 'Set up Touch ID';
  $('#helper-description').textContent = helperAvailable ? 'Your fingerprint stays with macOS. OpenLocker only receives a yes or no.' : helper.message || 'Install the Mac helper to connect Chrome to Touch ID.';
  $('#setup').hidden = helperAvailable;
}
async function render() {
  const { domains } = await request('STATUS');
  $('#domains').replaceChildren();
  $('#empty').hidden = domains.length > 0;
  for (const domain of domains) {
    const row = document.createElement('li');
    const label = document.createElement('div');
    label.className = 'name';
    label.textContent = domain;
    const detail = document.createElement('small');
    detail.textContent = 'Including subdomains';
    label.append(detail);
    const remove = document.createElement('button');
    remove.className = 'secondary';
    remove.textContent = 'Remove';
    remove.setAttribute('aria-label', `Remove ${domain} with Touch ID`);
    remove.addEventListener('click', () => busy(remove, async () => { await request('REMOVE_DOMAIN', { domain }); await render(); }, 'Touch ID…'));
    row.append(label, remove);
    $('#domains').append(row);
  }
}
$('#recheck').addEventListener('click', () => busy($('#recheck'), checkHelper));
$('#lock-all').addEventListener('click', () => busy($('#lock-all'), async () => { await request('LOCK_ALL'); notice('All protected tabs are locked.'); }));
$('#add-form').addEventListener('submit', event => {
  event.preventDefault();
  busy($('#add'), async () => {
    if (!helperAvailable) throw new Error('Set up the Mac helper above before locking your first site.');
    await request('LOCK_DOMAIN', { domain: $('#new-domain').value });
    $('#new-domain').value = '';
    await render();
    notice('Site locked. Touch ID will let you back in.');
  });
});
Promise.all([checkHelper(), render()]).catch(error => notice(error.message, true));
