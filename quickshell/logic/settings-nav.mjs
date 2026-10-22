const GROUP_ORDER = ['personalization', 'shell', 'behavior', 'system'];

export function flatPages(pages) {
  const rank = (group) => {
    const index = GROUP_ORDER.indexOf(group);
    return index === -1 ? GROUP_ORDER.length : index;
  };
  // The QML engine's sort is not stable, so catalog order breaks ties explicitly.
  return pages.map((page, index) => ({ page, index }))
    .sort((a, b) => rank(a.page.group) - rank(b.page.group) || a.index - b.index)
    .map(entry => entry.page);
}

function firstTabId(page) {
  return page?.tabs?.[0]?.id ?? '';
}

function pageById(pages, pageId) {
  return pages.find((page) => page.id === pageId);
}

export function initialNav(pages) {
  const first = flatPages(pages)[0];
  if (!first) return { pageId: '', tabId: '', query: '' };
  return { pageId: first.id, tabId: firstTabId(first), query: '' };
}

export function selectPage(nav, pages, pageId) {
  const page = pageById(pages, pageId);
  if (!page) return Object.assign({}, nav);
  return { pageId: page.id, tabId: firstTabId(page), query: '' };
}

export function selectTab(nav, pages, tabId) {
  const page = pageById(pages, nav.pageId);
  const belongs = page?.tabs?.some((tab) => tab.id === tabId) ?? false;
  if (!belongs) return Object.assign({}, nav);
  return Object.assign({}, nav, { tabId });
}

export function moveSelection(nav, pages, delta) {
  const flat = flatPages(pages);
  if (flat.length === 0) return Object.assign({}, nav);
  const current = flat.findIndex((page) => page.id === nav.pageId);
  let next;
  if (delta === 'first') next = 0;
  else if (delta === 'last') next = flat.length - 1;
  else if (current === -1) next = 0;
  else next = Math.min(Math.max(current + delta, 0), flat.length - 1);
  if (next === current) return Object.assign({}, nav);
  return selectPage(nav, pages, flat[next].id);
}
