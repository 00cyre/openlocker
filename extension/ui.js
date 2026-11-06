export const $ = selector => document.querySelector(selector);
export async function request(type, data = {}) {
  const response = await chrome.runtime.sendMessage({ type, ...data });
  if (!response?.ok) throw new Error(response?.error || 'OpenLocker could not connect. Please reload.');
  return response;
}
export function notice(message, error = false) {
  const target = $('#notice');
  target.textContent = message;
  target.classList.toggle('error', error);
  target.hidden = !message;
}
export async function busy(button, task, label = 'One moment…') {
  const previous = button.textContent;
  button.disabled = true;
  button.textContent = label;
  notice('');
  try { await task(); } catch (error) { notice(error.message, true); }
  finally { button.disabled = false; button.textContent = previous; }
}
export const fingerprint = `<svg viewBox="0 0 64 64" fill="none" aria-hidden="true"><g stroke="currentColor" stroke-width="2.6" stroke-linecap="round"><path d="M11 25c2-10 10-17 21-17s20 8 21 19"/><path d="M7 37v-4m50 2v-2M15 43c3-5 2-10 3-16a14 14 0 0 1 28 1c0 12-2 20-7 28"/><path d="M9 49c5-6 7-12 6-18M24 49c5-7 5-14 5-20a3 3 0 0 1 6 0c0 10-1 20-8 29M20 56l3-4M39 47c3-8 3-15 3-18a10 10 0 0 0-20 0c0 7 0 12-4 18M49 49c4-9 4-15 4-19"/></g></svg>`;
for (const element of document.querySelectorAll('[data-fingerprint]')) element.innerHTML = fingerprint;
