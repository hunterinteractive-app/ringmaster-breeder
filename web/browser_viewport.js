/* Safari can finish rotating with Flutter's keyboard inset reset to zero.
 * Recheck the visual viewport after rotation settles, keeping the active input
 * and its draft intact. Flutter remains responsible for sizing and scrolling.
 */
(() => {
  'use strict';
  const viewport = window.visualViewport;
  const ios = /iPad|iPhone|iPod/.test(navigator.userAgent) ||
    (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  if (!ios || !viewport) return;
  let timers = [];
  let settlingUntil = 0;
  const recheck = () => {
    const input = document.activeElement;
    if ((input?.tagName === 'INPUT' || input?.tagName === 'TEXTAREA') &&
        Math.abs(viewport.scale - 1) < 0.01 &&
        document.documentElement.clientHeight - viewport.height > 50) {
      // Safari can pan the document after Flutter has already scrolled its
      // own form. That second movement shifts the entire fixed app offscreen.
      if (window.scrollX || window.scrollY) window.scrollTo(0, 0);
      viewport.dispatchEvent(new Event('resize'));
    }
  };
  window.addEventListener('orientationchange', () => {
    timers.forEach(clearTimeout);
    settlingUntil = Date.now() + 2500;
    timers = [200, 500, 1000, 1500].map(delay => setTimeout(recheck, delay));
  });
  viewport.addEventListener('scroll', () => {
    if (Date.now() < settlingUntil && (window.scrollX || window.scrollY)) {
      recheck();
    }
  });
})();
