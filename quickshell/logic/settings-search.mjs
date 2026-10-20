const normalize = (value) => String(value).normalize('NFKC').toLocaleLowerCase().replace(/[’'ʼ]/g, '');

export function matches(query, text) {
    const haystack = normalize(text);
    return normalize(query).trim().split(/\s+/).every((word) => haystack.includes(word));
}

export function search(pages, query, lang) {
    const trimmed = String(query ?? '').trim();
    if (trimmed === '') return [];
    const results = [];
    for (const page of pages) {
        const pageText = [page.labelUk, page.labelEn, ...(page.keywords ?? [])];
        for (const section of page.sections ?? []) {
            for (const item of section.items ?? []) {
                const text = [...pageText, item.labelUk, item.labelEn, ...(item.keywords ?? [])].join(' ');
                if (matches(trimmed, text)) {
                    const hit = {
                        pageId: page.id,
                        sectionId: section.id,
                        key: item.key,
                        label: lang === 'uk' ? item.labelUk : item.labelEn
                    };
                    if (section.tab !== undefined) hit.tabId = section.tab;
                    results.push(hit);
                }
            }
        }
    }
    return results;
}
