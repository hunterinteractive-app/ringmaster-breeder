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
  window.addEventListener('orientationchange', () => {
    timers.forEach(clearTimeout);
    timers = [200, 500, 1000].map(delay => setTimeout(() => {
      const input = document.activeElement;
      if ((input?.tagName === 'INPUT' || input?.tagName === 'TEXTAREA') &&
          Math.abs(viewport.scale - 1) < 0.01 &&
          document.documentElement.clientHeight - viewport.height > 50) {
        viewport.dispatchEvent(new Event('resize'));
      }
    }, delay));
  });
})();
