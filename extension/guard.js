(() => {
  // Cover immediately, including a restored back/forward-cache document. This is
  // defense in depth; Chrome's persistent network rules are the primary gate.
  const cover = document.createElement('style');
  let shouldCover = true;
  let version = 0;
  let expiryTimer;
  let allowedUntil = 0;
  let allowedAt = 0;
  cover.textContent = 'html { visibility: hidden !important; opacity: 0 !important; pointer-events: none !important; background: #f5f5f2 !important; } @media (prefers-color-scheme: dark) { html { background: #151a16 !important; } }';
  function hide() {
    if (!shouldCover) return;
    if (cover.isConnected) return;
    if (document.documentElement) document.documentElement.appendChild(cover);
    else {
      const observer = new MutationObserver(() => {
        if (document.documentElement) { observer.disconnect(); hide(); }
      });
      observer.observe(document, { childList: true });
    }
  }
  function lock() {
    shouldCover = true;
    allowedUntil = 0;
    clearTimeout(expiryTimer);
    hide();
  }
  async function check() {
    const current = ++version;
    const time = Date.now();
    // Recheck focus quietly while this document's previous authorization is
    // still valid. Keep its deadline armed during the asynchronous request.
    if (shouldCover || time < allowedAt || time >= allowedUntil) lock();
    try {
      const result = await chrome.runtime.sendMessage({ type: 'GUARD' });
      if (current !== version) return;
      if (result?.ok && result.allowed) {
        const time = Date.now();
        if (Number.isFinite(result.expiresAt) && result.expiresAt <= time) {
          // The reply may arrive after its grant expired. Never reveal it,
          // even for one frame, while asking for a current decision.
          lock(); expiryTimer = setTimeout(check, 0); return;
        }
        allowedAt = time;
        allowedUntil = Number.isFinite(result.expiresAt) ? result.expiresAt : Infinity;
        shouldCover = false; cover.remove();
        clearTimeout(expiryTimer);
        if (Number.isFinite(allowedUntil)) expiryTimer = setTimeout(check, allowedUntil - time);
      }
      else {
        lock();
        if (result?.ok && result.redirect) location.replace(result.redirect);
      }
      // Fail closed if the worker is unavailable. Reload after restoring it.
    } catch { if (current === version) lock(); }
  }
  hide();
  check();
  addEventListener('pagehide', () => { version++; lock(); });
  addEventListener('pageshow', check);
  addEventListener('focus', check);
  addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible') check(); });
})();
