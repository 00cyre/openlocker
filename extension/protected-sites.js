import { MAX_DOMAINS, normalizeDomain } from './core.js';

function validList(value) {
  if (!Array.isArray(value) || value.length > MAX_DOMAINS) return null;
  try {
    if (!value.every(domain => normalizeDomain(domain) === domain)) return null;
    return [...new Set(value)].sort();
  } catch { return null; }
}

export async function saveProtectedSites(api, domains) {
  const value = validList(domains);
  if (!value) throw Error('The protected website list is invalid. Existing protection was kept.');
  // One atomic write. The separate copy also lets us recover older installations
  // with a missing primary key. Neither copy contains authentication grants.
  await api.storage.local.set({ domains: value, domainsBackup: { version: 1, domains: value } });
}

export async function loadProtectedSites(api) {
  const saved = await api.storage.local.get({ domains: null, domainsBackup: null });
  let domains = validList(saved.domains);
  // An explicitly saved empty list means the user removed all protection.
  if (domains === null && saved.domainsBackup?.version === 1) domains = validList(saved.domainsBackup.domains);
  if (domains === null) {
    const rules = await api.declarativeNetRequest.getDynamicRules();
    const recovered = rules.filter(rule => rule.priority === 10 &&
      ['block', 'redirect'].includes(rule.action?.type)).flatMap(rule => rule.condition?.requestDomains || []);
    // Each site has both a redirect rule and a block rule.
    domains = validList([...new Set(recovered)]);
    if (!domains || (!domains.length && (saved.domains !== null || saved.domainsBackup !== null))) {
      throw Error('OpenLocker could not recover its protected websites. Existing rules were kept.');
    }
  }
  await saveProtectedSites(api, domains);
  return domains;
}
