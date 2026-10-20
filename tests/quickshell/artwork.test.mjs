import test from 'node:test';
import assert from 'node:assert/strict';
import { artworkRequestIsCurrent, coverAccent, resolveArtwork } from '../../quickshell/logic/artwork.mjs';

test('monochrome covers retain the neutral fallback instead of inventing a hue', () => {
  assert.equal(coverAccent([
    { r: 0, g: 0, b: 0, a: 1 },
    { r: 0.5, g: 0.5, b: 0.5, a: 1 },
    { r: 1, g: 1, b: 1, a: 1 },
  ]), null);
  assert.equal(coverAccent([]), null);
});

test('cover accents score chromatic hues and use the muted saturation and lightness', () => {
  const tone = coverAccent([
    { r: 0.2, g: 0.2, b: 0.2, a: 1 },
    { r: 0.2, g: 0.2, b: 0.2, a: 1 },
    { r: 0.9, g: 0.1, b: 0.1, a: 1 },
    { r: 0.1, g: 0.1, b: 0.9, a: 0 },
  ]);
  assert.equal(tone.hue, 0);
  assert.equal(tone.saturation, 0.38);
  assert.equal(tone.lightness, 0.64);
});

test('keeps safe HTTP artwork and derives YouTube thumbnails', () => {
  assert.deepEqual(resolveArtwork('https://cdn.example/cover.jpg', '', 'vlc'), {
    urls: ['https://cdn.example/cover.jpg'], mark: '',
  });
  assert.deepEqual(resolveArtwork('', 'https://www.youtube.com/watch?v=abcdefghijk', 'firefox'), {
    urls: ['https://i.ytimg.com/vi/abcdefghijk/hqdefault.jpg'], mark: 'youtube',
  });
});

test('allows absolute local artwork file URIs, including localhost authority', () => {
  assert.deepEqual(resolveArtwork('file:///home/user/Music/cover%20art.jpg', '', 'vlc'), {
    urls: ['file:///home/user/Music/cover%20art.jpg'], mark: '',
  });
  assert.deepEqual(resolveArtwork('file://localhost/home/user/cover.jpg', '', 'vlc'), {
    urls: ['file://localhost/home/user/cover.jpg'], mark: '',
  });
});

test('rejects remote file authorities, credentials, and non-image URL schemes', () => {
  for (const uri of [
    'file://server/share/cover.jpg',
    'file://user@localhost/home/cover.jpg',
    'file:relative/cover.jpg',
    'file:///home/user/cover.jpg?token=secret',
    'data:image/png;base64,AAAA',
    'javascript:alert(1)',
  ]) {
    assert.deepEqual(resolveArtwork(uri, '', 'vlc'), { urls: [], mark: '' }, uri);
  }
});

test('artwork completion publishes only for the current generation and track key', () => {
  assert.equal(artworkRequestIsCurrent(12, 12, 'track-a', 'track-a'), true);
  assert.equal(artworkRequestIsCurrent(13, 12, 'track-a', 'track-a'), false);
  assert.equal(artworkRequestIsCurrent(12, 12, 'track-b', 'track-a'), false);
  assert.equal(artworkRequestIsCurrent(Number.MAX_SAFE_INTEGER + 1, 12, 'track-a', 'track-a'), false);
});

test('a late completion from a prior track cannot overwrite the latest cover', async () => {
  let generation = 1;
  let key = 'track-a';
  const visible = [];
  const start = (requestGeneration, requestKey) => (value) => {
    if (artworkRequestIsCurrent(generation, requestGeneration, key, requestKey)) visible.push(value);
  };
  const oldCompletion = start(generation, key);
  generation += 1;
  key = 'track-b';
  const currentCompletion = start(generation, key);
  currentCompletion('cover-b');
  await Promise.resolve();
  oldCompletion('cover-a');
  assert.deepEqual(visible, ['cover-b']);
});
