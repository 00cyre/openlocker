(() => {
  // Only genuine input in a visible document counts. Send no keys, text,
  // coordinates, or event contents. The worker verifies the active tab/window.
  let lastSent = -Infinity;
  const record = event => {
    if (!event.isTrusted || document.visibilityState !== 'visible') return;
    const now = Date.now();
    if (now - lastSent < 1000) return;
    lastSent = now;
    chrome.runtime.sendMessage({ type: 'ACTIVITY' }).catch(() => {});
  };
  for (const type of ['pointerdown', 'pointermove', 'keydown', 'wheel', 'touchstart']) {
    addEventListener(type, record, { capture: true, passive: true });
  }
})();
