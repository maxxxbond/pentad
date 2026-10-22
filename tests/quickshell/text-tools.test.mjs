import test from 'node:test';
import assert from 'node:assert/strict';
import * as T from '../../quickshell/logic/text-tools.mjs';

const NOW = Date.UTC(2024, 0, 15, 12, 0, 0);

test('base64 and base64url round-trip UTF-8 and match Buffer', () => {
  const s = 'Grüße 😀';
  for (const [mode, url] of [['base64', false], ['base64url', true]]) {
    const enc = T.encodeText(mode, s);
    assert.equal(enc.value, Buffer.from(s).toString(url ? 'base64url' : 'base64'));
    assert.deepEqual(T.decodeText(mode, enc.value), { ok: true, value: s });
  }
  assert.equal(T.decodeText('base64', 'aGk').value, 'hi');
  assert.equal(T.decodeText('base64', '!!!').ok, false);
  assert.equal(T.decodeText('base64', '/w==').ok, false);
});

test('url, html and hex codecs', () => {
  assert.equal(T.encodeText('url', 'a b&c=Grüße').value, 'a%20b%26c%3DGr%C3%BC%C3%9Fe');
  assert.equal(T.decodeText('url', 'Gr%C3%BC%C3%9Fe').value, 'Grüße');
  assert.equal(T.decodeText('url', '%E0%A4%A').ok, false);
  assert.equal(T.encodeText('html', '<a href="x">&\'</a>').value, '&lt;a href=&quot;x&quot;&gt;&amp;&#39;&lt;/a&gt;');
  assert.equal(T.decodeText('html', '&lt;b&gt; &#x1F600; &#65; &bogus;').value, '<b> 😀 A &bogus;');
  assert.equal(T.encodeText('hex', 'Grüße 😀').value, '4772c3bcc39f6520f09f9880');
  assert.equal(T.decodeText('hex', '47 72:c3 bc 0xc3 0x9f 65').value, 'Grüße');
  assert.equal(T.decodeText('hex', 'abc').ok, false);
  assert.equal(T.encodeText('jwt', 'x').ok, false);
});

const jwt = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4iLCJpYXQiOjE1MTYyMzkwMjIsImV4cCI6MTcwNTMyMDAwMH0.sig';
test('decodes JWT with human-readable times', () => {
  const r = T.decodeText('jwt', jwt, NOW);
  assert.equal(r.ok, true);
  assert.match(r.value, /"alg": "HS256"/);
  assert.match(r.value, /"sub": "1234567890"/);
  assert.match(r.value, /iat: 2018-01-18T01:30:22.000Z/);
  assert.match(r.value, /exp: 2024-01-15T12:00:00.000Z \(just now\)/);
  assert.match(r.value, /Signature not verified/);
  assert.equal(T.decodeText('jwt', 'a.b').ok, false);
  assert.equal(T.decodeText('jwt', 'eyJ.@@.x').ok, false);
});

test('auto decode detects the encoding', () => {
  assert.equal(T.autoDecode(jwt, NOW).mode, 'jwt');
  assert.deepEqual(T.autoDecode('Gr%C3%BC%C3%9Fe'), { ok: true, value: 'Grüße', mode: 'url' });
  assert.equal(T.autoDecode('48656c6c6f').mode, 'hex');
  assert.deepEqual(T.autoDecode('SGVsbG8sIHdvcmxkIQ=='), { ok: true, value: 'Hello, world!', mode: 'base64' });
  assert.equal(T.autoDecode('&lt;p&gt;').mode, 'html');
  assert.equal(T.autoDecode('').ok, false);
  assert.equal(T.autoDecode('???').ok, false);
});

test('parses and formats timestamps', () => {
  assert.deepEqual(T.parseTimestamp('1705320000'), { ok: true, value: 1705320000000, unit: 'seconds' });
  assert.deepEqual(T.parseTimestamp('1705320000123'), { ok: true, value: 1705320000123, unit: 'milliseconds' });
  assert.equal(T.parseTimestamp('2024-01-15T12:00:00Z').value, NOW);
  assert.equal(T.parseTimestamp('Mon, 15 Jan 2024 12:00:00 GMT').value, NOW);
  assert.equal(T.parseTimestamp('nope').ok, false);
  assert.equal(T.parseTimestamp('').ok, false);
  const rows = T.convertTimestamp('1705320000', NOW + 3 * 3600 * 1000).value;
  assert.deepEqual(rows.map(r => r.id), ['seconds', 'milliseconds', 'iso', 'local', 'relative']);
  assert.equal(rows[0].value, '1705320000');
  assert.equal(rows[1].value, '1705320000000');
  assert.equal(rows[2].value, '2024-01-15T12:00:00.000Z');
  assert.match(rows[3].value, /^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d \(UTC[+-]\d\d:\d\d\)$/);
  assert.equal(rows[4].value, '3 hours ago');
});

test('relative time wording', () => {
  assert.equal(T.relativeTime(NOW + 2 * 86400000, NOW), 'in 2 days');
  assert.equal(T.relativeTime(NOW - 86400000, NOW), '1 day ago');
  assert.equal(T.relativeTime(NOW + 1000, NOW), 'just now');
  assert.equal(T.relativeTime(NOW - 90 * 1000, NOW), '1 minute ago');
  assert.equal(T.relativeTime(NOW + 400 * 86400000, NOW), 'in 1 year');
  assert.equal(T.convertTimestamp('99999999999999999999', NOW).ok, false);
});

test('parses all color syntaxes', () => {
  const red = { r: 255, g: 0, b: 0, a: 1 };
  for (const s of ['#f00', '#ff0000', 'ff0000', 'rgb(255 0 0)', 'rgb(255, 0, 0)', 'rgb(100%, 0%, 0%)', 'hsl(0, 100%, 50%)', 'hsl(0deg 100% 50%)', '#FF0000FF', '#f00f']) {
    const c = T.parseColor(s);
    assert.equal(c.ok, true, s);
    assert.ok(Math.abs(c.value.r - 255) < 0.5 && c.value.g < 0.5 && c.value.b < 0.5 && c.value.a === 1, s);
  }
  assert.equal(T.parseColor('#12abef80').value.a, 128 / 255);
  assert.equal(T.parseColor('rgba(0, 0, 0, 0.5)').value.a, 0.5);
  assert.equal(T.parseColor('rgb(0 0 0 / 25%)').value.a, 0.25);
  const lch = T.parseColor('oklch(62.8% 0.2577 29.23)').value;
  assert.ok(Math.abs(lch.r - 255) < 1.5 && lch.g < 6 && lch.b < 6);
  assert.equal(T.parseColor('#12').ok, false);
  assert.equal(T.parseColor('rgb(1 2)').ok, false);
  assert.equal(T.parseColor('banana').ok, false);
  assert.deepEqual(red, { r: 255, g: 0, b: 0, a: 1 });
});

test('formats colors with correct OKLCH math and gamut clamp', () => {
  const red = T.convertColor('#ff0000').value;
  assert.equal(red.hex, '#ff0000');
  assert.equal(red.rgb, 'rgb(255, 0, 0)');
  assert.equal(red.hsl, 'hsl(0, 100%, 50%)');
  assert.equal(red.oklch, 'oklch(62.8% 0.2577 29.23)');
  assert.equal(T.convertColor('white').ok, false);
  assert.equal(T.convertColor('#ffffff').value.oklch, 'oklch(100% 0 0)');
  assert.equal(T.convertColor('#000').value.oklch, 'oklch(0% 0 0)');
  const alpha = T.convertColor('#12abef80').value;
  assert.equal(alpha.hex, '#12abef80');
  assert.match(alpha.rgb, /^rgba\(18, 171, 239, 0\.502\)$/);
  // Out-of-gamut oklch is clamped into valid sRGB.
  const wide = T.convertColor('oklch(70% 0.4 150)').value;
  assert.match(wide.hex, /^#[0-9a-f]{6}$/);
  assert.equal(T.convertColor('hsl(120 100% 25%)').value.hex, '#008000');
});

test('splits words across naming styles', () => {
  assert.deepEqual(T.splitWords('helloWorld foo_bar-baz  Qux'), ['hello', 'World', 'foo', 'bar', 'baz', 'Qux']);
  assert.deepEqual(T.splitWords('HTMLParser2Go'), ['HTML', 'Parser2', 'Go']);
  assert.deepEqual(T.splitWords('привіт світ, ÉcoleNormale'), ['привіт', 'світ', 'École', 'Normale']);
  assert.deepEqual(T.splitWords("don't stop"), ["don't", 'stop']);
  assert.deepEqual(T.splitWords('  ---  '), []);
});

test('converts text case', () => {
  const c = (m, s) => T.convertCase(m, s).value;
  assert.equal(c('lower', 'Hello WORLD'), 'hello world');
  assert.equal(c('upper', 'Straße'), 'STRASSE');
  assert.equal(c('title', "hello wORLD, it's me"), "Hello World, It's Me");
  assert.equal(c('sentence', 'hELLO there. how ARE you?\nfine'), 'Hello there. How are you?\nFine');
  assert.equal(c('camel', 'Hello big_world-wide'), 'helloBigWorldWide');
  assert.equal(c('pascal', 'hello big_world'), 'HelloBigWorld');
  assert.equal(c('snake', 'helloBigWorld'), 'hello_big_world');
  assert.equal(c('kebab', 'Hello Big World'), 'hello-big-world');
  assert.equal(c('constant', 'helloBigWorld'), 'HELLO_BIG_WORLD');
  assert.equal(c('snake', 'one two\nthreeFour'), 'one_two\nthree_four');
  assert.equal(c('camel', 'привіт світ'), 'привітСвіт');
  assert.equal(T.convertCase('x', 'a').ok, false);
});

test('slugs transliterate Latin diacritics and Ukrainian', () => {
  const s = x => T.convertCase('slug', x).value;
  assert.equal(s('Crème Brûlée à la façon de Zoë!'), 'creme-brulee-a-la-facon-de-zoe');
  assert.equal(s('Straße Größe'), 'strasse-grosse');
  assert.equal(s('Київ'), 'kyiv');
  assert.equal(s('Єнакієве'), 'yenakiieve');
  assert.equal(s('Їжак Юрій Яблуко'), 'yizhak-yurii-yabluko');
  assert.equal(s('Гадяч Згорани'), 'hadiach-zghorany');
  assert.equal(s('Щастя ґанок м\'ясо'), 'shchastia-ganok-miaso');
  assert.equal(s('Олексій Мар\'їна'), 'oleksii-marina');
  assert.equal(s('helloWorld'), 'hello-world');
  assert.equal(s('!!!'), '');
});

test('text stats count code points, words, lines and UTF-8 bytes', () => {
  assert.deepEqual(T.textStats(''), { characters: 0, words: 0, lines: 0, bytes: 0 });
  assert.deepEqual(T.textStats('Grüße 😀\nok'), { characters: 10, words: 3, lines: 2, bytes: 15 });
});

test('utf8 decode rejects invalid sequences', () => {
  assert.equal(T.utf8Decode([0xC0, 0x80]).ok, false);
  assert.equal(T.utf8Decode([0xE2, 0x82]).ok, false);
  assert.equal(T.utf8Decode([0xED, 0xA0, 0x80]).ok, false);
  assert.equal(T.utf8Decode(T.utf8Encode('Grüße 😀')).value, 'Grüße 😀');
});
