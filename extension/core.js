export const HOST = 'cc.openlocker.touchid';
export const MAX_DOMAINS = 500;

export function webURL(value) {
  try {
    const url = new URL(value);
    if (!['http:', 'https:'].includes(url.protocol) || url.username || url.password) return null;
    return url;
  } catch { return null; }
}

export function normalizeDomain(value) {
  if (typeof value !== 'string' || !value.trim()) throw new Error('Enter a website, like example.com.');
  const input = value.trim();
  const url = webURL(input.includes('://') ? input : `https://${input}`);
  if (!url) throw new Error('Use an http or https website address.');
  const domain = url.hostname.toLowerCase().replace(/\.$/, '').replace(/^www\./, '');
  if (domain.length > 253 || !/^(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)*[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/.test(domain)) {
    throw new Error('Enter a valid domain name. IPv6 addresses are not supported.');
  }
  return domain;
}

export function matches(host, domain) {
  host = host.toLowerCase().replace(/\.$/, '');
  return host === domain || host.endsWith(`.${domain}`);
}

export function protectedDomain(url, domains) {
  const host = webURL(url)?.hostname;
  return host ? domains.filter(d => matches(host, d)).sort((a, b) => b.length - a.length)[0] || null : null;
}

export function lockedURL(base, url) {
  if (!webURL(url)) throw new Error('This page cannot be locked.');
  return `${base}locked.html#${url}`;
}

export function originalURL(url, base) {
  if (url?.startsWith(`${base}locked.html#`)) return webURL(url.slice(`${base}locked.html#`.length))?.href || null;
  return webURL(url)?.href || null;
}

export function domainRules(domains, base) {
  return [...domains].sort().flatMap((domain, index) => [
    {
      id: index * 2 + 1, priority: 10,
      action: { type: 'redirect', redirect: { regexSubstitution: `${base}locked.html#\\0` } },
      condition: { requestDomains: [domain], regexFilter: '^https?://.*', resourceTypes: ['main_frame'] }
    },
    {
      id: index * 2 + 2, priority: 10,
      action: { type: 'block' },
      condition: { requestDomains: [domain], excludedResourceTypes: ['main_frame'] }
    }
  ]);
}

export function grantRule(grant) {
  return {
    id: grant.tabId + 1, priority: 100,
    action: { type: 'allow' },
    // Chrome's default excludes main_frame, even with an empty exclusion list.
    // Specify the types explicitly so authentication also allows navigation.
    condition: {
      requestDomains: [grant.domain], tabIds: [grant.tabId],
      resourceTypes: ['main_frame', 'sub_frame', 'stylesheet', 'script', 'image',
        'font', 'object', 'xmlhttprequest', 'ping', 'csp_report', 'media',
        'websocket', 'webtransport', 'webbundle', 'other']
    }
  };
}

export function trustedPage(sender, base, pages) {
  if (sender.frameId && sender.frameId !== 0) return false;
  try {
    const url = new URL(sender.url);
    return url.origin === new URL(base).origin && sender.url.startsWith(base) && pages.includes(url.pathname.slice(1));
  } catch { return false; }
}
