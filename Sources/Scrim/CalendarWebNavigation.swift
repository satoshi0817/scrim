import Foundation

/// Reuse the site's own Today action, after its asynchronously rendered toolbar appears.
/// Never changes the user's week/day view, calendars, or account settings.
enum CalendarWebNavigation {
    static let cancel = "window.__scrimTodayReset?.cancel();"
    static let today = """
    (() => {
      window.__scrimTodayReset?.cancel();
      let observer, timer, deadline;
      const cancel = () => { observer?.disconnect(); clearInterval(timer); clearTimeout(deadline); delete window.__scrimTodayReset; };
      window.__scrimTodayReset = { cancel };
      const reset = () => {
        const labels = /^(today|今日|今日に戻る|go to today)$/i;
        const button = [...document.querySelectorAll('button, [role="button"]')].find(el => {
          const r = el.getBoundingClientRect();
          return r.width > 0 && r.height > 0 && !el.disabled && el.getAttribute('aria-disabled') !== 'true'
            && [el.textContent, el.getAttribute('aria-label'), el.getAttribute('title')].some(value => labels.test((value || '').trim()));
        });
        if (button) { cancel(); button.click(); return true; }
        return false;
      };
      if (!reset()) {
        observer = new MutationObserver(reset);
        observer.observe(document.documentElement, { childList: true, subtree: true, attributes: true });
        timer = setInterval(reset, 250);
        deadline = setTimeout(cancel, 10000);
      }
    })();
    """
}
