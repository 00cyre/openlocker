export const RELEASES = 'https://github.com/00cyre/openlocker/releases/latest';
const endpoint = 'https://api.github.com/repos/00cyre/openlocker/releases/latest';
export function versionParts(value) {
  return typeof value === 'string' && /^(0|[1-9]\d{0,7})\.(0|[1-9]\d{0,7})\.(0|[1-9]\d{0,7})$/.test(value) ? value.split('.').map(Number) : null;
}
export function isNewer(candidate, installed) {
  const a = versionParts(candidate), b = versionParts(installed);
  if (!a || !b) return false;
  for (let i = 0; i < 3; i++) { if (a[i] !== b[i]) return a[i] > b[i]; }
  return false;
}
export function releaseVersion(value) {
  const version = value?.tag_name?.startsWith('v') ? value.tag_name.slice(1) : '';
  if (!versionParts(version) || value.draft !== false || value.prerelease !== false) throw Error('Invalid update information.');
  const name = `OpenLocker-${version}-macOS.dmg`;
  const asset = value.assets?.find(asset => asset.name === name);
  if (asset?.browser_download_url !== `https://github.com/00cyre/openlocker/releases/download/v${version}/${name}` || !(asset.size > 0 && asset.size <= 100_000_000)) throw Error('This release has no supported Mac update.');
  return version;
}
export async function isManagedInstallation() {
  try { const response = await fetch(chrome.runtime.getURL('installation.json')); return response.ok && (await response.json()).managed === true; }
  catch { return false; }
}
export async function updateStatus(force = false) {
  let { updateCheck } = await chrome.storage.local.get({ updateCheck: null });
  if (force || !versionParts(updateCheck?.version) || !(Date.now() - updateCheck.checkedAt >= 0 && Date.now() - updateCheck.checkedAt < 3_600_000)) {
    const response = await fetch(endpoint, { headers: { Accept: 'application/vnd.github+json' }, signal: AbortSignal.timeout(20_000) });
    if (!response.ok) throw Error('Could not check for updates. Try again when online.');
    updateCheck = { version: releaseVersion(await response.json()), checkedAt: Date.now() };
    await chrome.storage.local.set({ updateCheck });
  }
  const managed = await isManagedInstallation();
  const installed = chrome.runtime.getManifest().version;
  return { installed, version: updateCheck.version, available: isNewer(updateCheck.version, installed), managed };
}
