import assert from 'node:assert/strict';
import { test } from 'node:test';
import { overviewPage, overviewColumns, overviewSceneLayout, fitPreview, projectWindow } from '../../quickshell/logic/overview-layout.mjs';

test('numeric pages use global IDs and named active workspace falls back to first page', () => {
    assert.deepEqual(overviewPage(13), { start: 11, ids: ['11','12','13','14','15','16','17','18','19','20'] });
    assert.deepEqual(overviewPage('special:music'), { start: 1, ids: ['1','2','3','4','5','6','7','8','9','10'] });
    assert.equal(overviewPage(10).start, 1);
    assert.equal(overviewPage(11).start, 11);
});

test('columns adapt at the tile plus gap threshold', () => {
    assert.equal(overviewColumns(1024), 4);
    assert.equal(overviewColumns(400), 1);
    assert.equal(overviewColumns(192), 1);
    assert.equal(overviewColumns(975), 4);
    assert.equal(overviewColumns(451), 1);
    assert.equal(overviewColumns(452), 2);
    assert.equal(overviewColumns(1148), 5);
    for (const width of [452, 680, 975, 1024, 1148, 1800]) {
        const columns = overviewColumns(width);
        assert.ok((width - (columns - 1) * 12) / columns >= 220);
    }
});

test('window projection preserves geometry across negative output origins', () => {
    assert.deepEqual(projectWindow(
        { x: -1820, y: 124, width: 800, height: 600 },
        { x: -1920, y: 24, width: 1600, height: 900 },
        { width: 320, height: 180 },
    ), { x: 20, y: 20, width: 160, height: 120 });
});

test('scene and rail fit landscape, ultrawide, portrait and scaled logical viewports', () => {
    const viewports = [[1920,1080], [3440,1440], [1080,1920], [1366,768], [960,540], [360,640], [320,180], [0,0]];
    for (const [width,height] of viewports) for (const expanded of [false,true]) {
        const layout = overviewSceneLayout(width,height,{expanded,pinned:true});
        for (const box of [layout.scene,layout.rail]) {
            assert.ok(Object.values(box).every(Number.isFinite));
            assert.ok(box.width >= 0 && box.height >= 0);
            assert.ok(box.x >= 0 && box.y >= 0);
            assert.ok(box.x + box.width <= width + 0.01);
            assert.ok(box.y + box.height <= height + 0.01);
        }
        if (layout.side) assert.ok(layout.scene.x + layout.scene.width <= layout.rail.x);
        else assert.ok(layout.scene.y + layout.scene.height <= layout.rail.y);
    }
    assert.equal(overviewSceneLayout(3440,1440).side,true);
    assert.equal(overviewSceneLayout(1920,1080).side,false);
    assert.equal(overviewSceneLayout(1080,1920).side,false);
    assert.ok(overviewSceneLayout(1920,1080,{expanded:true}).rail.height > overviewSceneLayout(1920,1080).rail.height);
    assert.ok(overviewSceneLayout(3440,1440,{expanded:true}).rail.width > overviewSceneLayout(3440,1440).rail.width);
});

test('mixed monitor previews preserve portrait and ultrawide geometry inside the same scene', () => {
    const box = overviewSceneLayout(1920,1080).scene;
    for (const [width,height] of [[1080,1920],[3440,1440],[1920,1080]]) {
        const preview = fitPreview(width,height,box.width,box.height);
        assert.ok(preview.width <= box.width + 1 && preview.height <= box.height + 1);
        assert.ok(Math.abs(preview.width / preview.height - width / height) < 0.01);
        const left = projectWindow({x:0,y:0,width:width/2,height}, {x:0,y:0,width,height}, preview);
        assert.ok(Math.abs(left.width - preview.width/2) <= 1);
    }
});

test('adjacent tiled clients keep separate half-width rectangles', () => {
    const workarea = { x: 0, y: 40, width: 1920, height: 1040 };
    const tile = { width: 202, height: 146 };
    const left = projectWindow({ x: 0, y: 40, width: 960, height: 1040 }, workarea, tile);
    const right = projectWindow({ x: 960, y: 40, width: 960, height: 1040 }, workarea, tile);
    assert.deepEqual(left, { x: 0, y: 18, width: 101, height: 110 });
    assert.deepEqual(right, { x: 101, y: 18, width: 101, height: 110 });
    assert.equal(left.x + left.width, right.x);
});

test('projection handles portrait workareas, clipping and absent geometry', () => {
    assert.deepEqual(projectWindow(
        { x: 0, y: 400, width: 600, height: 800 },
        { x: 0, y: 0, width: 900, height: 1600 },
        { width: 180, height: 160 },
    ), { x: 45, y: 40, width: 60, height: 80 });
    assert.deepEqual(projectWindow(
        { x: -100, y: -50, width: 300, height: 200 },
        { x: 0, y: 0, width: 1000, height: 500 },
        { width: 200, height: 100 },
    ), { x: 0, y: 0, width: 40, height: 30 });
    assert.deepEqual(projectWindow(
        { x: -400, y: 400, width: 600, height: 800 },
        { x: 0, y: 0, width: 900, height: 1600 },
        { width: 180, height: 160 },
    ), { x: 45, y: 40, width: 20, height: 80 });
    assert.equal(projectWindow({ x: 0, y: 0, width: 100, height: 100 },
        { x: 0, y: 0, width: 0, height: 100 }, { width: 200, height: 100 }), null);
    assert.equal(projectWindow({ x: 4000, y: 0, width: 100, height: 100 },
        { x: 0, y: 0, width: 1000, height: 500 }, { width: 200, height: 100 }), null);
});

test('overview grid keeps five columns on wide screens and shrinks columns only when cells get too small', async () => {
  const { overviewGridLayout } = await import('../../quickshell/logic/overview-layout.mjs');
  const aspect = 1040 / 1920;
  const wide = overviewGridLayout(2560, 1400, { aspect, count: 10 });
  assert.equal(wide.columns, 5);
  assert.equal(wide.rows, 2);
  assert.ok(Math.abs(wide.cellHeight / wide.cellWidth - aspect) < 0.01);
  assert.ok(wide.x >= 0 && wide.x + wide.width <= 2560 && wide.y + wide.height <= 1400);
  const medium = overviewGridLayout(1000, 800, { aspect, count: 10 });
  assert.equal(medium.columns, 4);
  assert.equal(medium.rows, 3);
  const narrow = overviewGridLayout(600, 900, { aspect, count: 10 });
  assert.equal(narrow.columns, 2);
  assert.ok(narrow.cellWidth >= 190);
});

test('overview grid cells never overflow the available area and tolerate degenerate input', async () => {
  const { overviewGridLayout } = await import('../../quickshell/logic/overview-layout.mjs');
  for (const [w, h, aspect] of [[1192, 824, 0.54], [1192, 300, 0.54], [900, 1600, 1.78], [NaN, 500, 0.5], [0, 0, 0.5], [800, 600, -1]]) {
    const grid = overviewGridLayout(w, h, { aspect, count: 10, pinned: true });
    assert.ok(Number.isFinite(grid.cellWidth) && grid.cellWidth >= 0 && Number.isFinite(grid.cellHeight));
    assert.ok(grid.columns >= 1 && grid.rows * grid.columns >= 10);
    if (w > 0 && h > 0) assert.ok(grid.x + grid.width <= (Number.isFinite(w) ? w : 0) + 1 || !Number.isFinite(w));
  }
});

test('overview cards keep their own shapes: portrait monitor and 4:3 game beside 16:9 desktops', async () => {
  const { overviewGridLayout } = await import('../../quickshell/logic/overview-layout.mjs');
  const landscape = 1040 / 1920;
  const portrait = 1880 / 1080;
  const game = 3 / 4;
  const aspects = [landscape, landscape, landscape, landscape, landscape, portrait, landscape, landscape, landscape, game];
  const grid = overviewGridLayout(2000, 1187, { aspect: landscape, aspects, count: 10 });
  assert.equal(grid.cells.length, 10);
  assert.equal(grid.columns, 5);
  grid.cells.forEach((cell, index) => {
    assert.ok(Math.abs(cell.height / cell.width - aspects[index]) < 0.02, `card ${index + 1} keeps its shape`);
    assert.equal(cell.height, grid.cellHeight);
    assert.ok(cell.x >= 0 && cell.x + cell.width <= grid.width + 1 && cell.y + cell.height <= grid.height + 1);
  });
  assert.ok(grid.cells[5].width < grid.cells[6].width / 2, 'the portrait card is narrow, not a letterboxed strip');
  assert.ok(grid.cells.slice(0, 5).every(cell => cell.y === 0) && grid.cells.slice(5).every(cell => cell.y > 0));
  for (let index = 1; index < 5; index++) assert.ok(grid.cells[index].x > grid.cells[index - 1].x + grid.cells[index - 1].width);
  assert.ok(grid.x >= 0 && grid.x + grid.width <= 2000 && grid.y + grid.height <= 1187);
  const uniform = overviewGridLayout(2000, 1187, { aspect: landscape, count: 10 });
  assert.ok(uniform.cells.every(cell => cell.width === uniform.cells[0].width));
});
