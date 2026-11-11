/** Presentation adapter: caller owns preference storage; this module never writes storage. */
export function bindKanyuV6Theme(getPreference, root) {
  if (typeof window === 'undefined' || typeof document === 'undefined') {
    return { refresh() {}, dispose() {} };
  }
  const target = root || document.documentElement;
  const query = window.matchMedia('(prefers-color-scheme: dark)');
  const refresh = () => {
    const preference = getPreference();
    target.dataset.kanyuTheme = preference === 'light' || preference === 'dark'
      ? preference : (query.matches ? 'dark' : 'light');
  };
  refresh();
  if (query.addEventListener) query.addEventListener('change', refresh);
  else query.addListener(refresh);
  return {
    refresh,
    dispose() {
      if (query.removeEventListener) query.removeEventListener('change', refresh);
      else query.removeListener(refresh);
    }
  };
}
