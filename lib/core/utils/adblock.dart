/// JavaScript to block ads, popups, and overlays in WebView.
const String adBlockScript = '''
(function() {
  // Block window.open popups
  window.open = function() { return null; };

  // Block common ad selectors
  const adSelectors = [
    'iframe[src*="ads"]', 'iframe[src*="doubleclick"]', 'iframe[src*="googlesyndication"]',
    'div[class*="ads"]', 'div[class*="ad-"]', 'div[id*="ads"]', 'div[id*="ad-"]',
    'div[class*="banner"]', 'div[class*="popup"]', 'div[class*="modal"]',
    'div[class*="overlay"]', 'ins.adsbygoogle', '.adsbygoogle',
    'div[class*="sponsor"]', 'a[href*="redirect"]',
    'div[class*="notification"]', 'div[class*="push"]',
    'div[class*="download"]', 'div[class*="click-here"]',
    'div[style*="z-index"][style*="position: fixed"]',
    'div[style*="z-index"][style*="position: absolute"]',
  ];

  function removeAds() {
    for (const sel of adSelectors) {
      document.querySelectorAll(sel).forEach(el => {
        el.remove();
      });
    }
    // Remove fixed/sticky overlays
    document.querySelectorAll('div, section').forEach(el => {
      const style = window.getComputedStyle(el);
      if ((style.position === 'fixed' || style.position === 'sticky') &&
          style.zIndex > 999 && el.offsetHeight < window.innerHeight * 0.5) {
        el.remove();
      }
    });
  }

  removeAds();
  // Re-run periodically to catch dynamically loaded ads
  setInterval(removeAds, 2000);

  // Prevent beforeunload popups
  window.onbeforeunload = null;
  window.addEventListener('beforeunload', function(e) { e.stopImmediatePropagation(); }, true);
})();
''';
