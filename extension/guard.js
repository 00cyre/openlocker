(() => {
  // Cover immediately, including a restored back/forward-cache document. This is
  // defense in depth; Chrome's persistent network rules are the primary gate.
  const cover = document.createElement('style');
  let shouldCover = true;
  let version = 0;
  let expiryTimer;
  cover.textContent = 'html { visibility: hidden !important; opacity: 0 !important; pointer-events: none !important; background: #f5f5f2 !important; }';
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
  async function check() {
    const current = ++version;
    clearTimeout(expiryTimer);
    shouldCover = true;
    hide();
    try {
      const result = await chrome.runtime.sendMessage({ type: 'GUARD' });
      if (current !== version) return;
      if (result?.ok && result.allowed) {
        shouldCover = false; cover.remove();
        if (Number.isFinite(result.expiresAt)) expiryTimer = setTimeout(check, Math.max(0, result.expiresAt - Date.now()));
      }
      else if (result?.ok && result.redirect) location.replace(result.redirect);
      // Fail closed if the worker is unavailable. Reload after restoring it.
    } catch { /* Keep the document covered. */ }
  }
  hide();
  check();
  addEventListener('pagehide', () => { version++; clearTimeout(expiryTimer); shouldCover = true; hide(); });
  addEventListener('pageshow', check);
  addEventListener('focus', check);
  addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible') check(); });
})();
