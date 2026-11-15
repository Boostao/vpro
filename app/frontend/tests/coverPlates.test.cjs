const test = require('node:test');
const assert = require('node:assert/strict');
const { loadTypeScript } = require('./svelteTestHelpers.cjs');

const bindingsStub = {
  DataService: {},
  SyncService: {},
  WorkflowService: {},
  ProjectService: {},
  ExportService: {},
  ReportService: {},
  ImportService: {},
  GISService: {},
  SettingsService: {},
  VListsService: {},
  CloudService: {},
  MessageService: {},
  HelpService: {},
  DiagnosticService: {},
  SystemService: {},
  Events: {},
};

const { COVER_COMPARISON_BLOCKS } = loadTypeScript('helpSystem.ts', {
  '../../bindings/github.com/boostao/vpro/app': bindingsStub,
});

function computeRectUnionArea(rects) {
  const xs = Array.from(new Set(rects.flatMap((r) => [r.x, r.x + r.w]))).sort((a, b) => a - b);
  let total = 0;
  for (let i = 0; i < xs.length - 1; i += 1) {
    const x0 = xs[i];
    const x1 = xs[i + 1];
    const width = x1 - x0;
    if (width <= 0) continue;

    const yIntervals = rects
      .filter((r) => r.x <= x0 && r.x + r.w >= x1)
      .map((r) => [r.y, r.y + r.h])
      .sort((a, b) => a[0] - b[0] || a[1] - b[1]);

    let coveredY = 0;
    let curStart = null;
    let curEnd = null;
    for (const [start, end] of yIntervals) {
      if (curStart === null) {
        curStart = start;
        curEnd = end;
      } else if (start > curEnd) {
        coveredY += curEnd - curStart;
        curStart = start;
        curEnd = end;
      } else if (end > curEnd) {
        curEnd = end;
      }
    }
    if (curStart !== null && curEnd > curStart) {
      coveredY += curEnd - curStart;
    }
    total += width * coveredY;
  }
  return total;
}

test('COVER_COMPARISON_BLOCKS cover plates have zero overlap and exact LMH25 area percentage', () => {
  const percents = Array.from(COVER_COMPARISON_BLOCKS, (b) => b.percent);
  assert.deepEqual(
    percents,
    [0.1, 1, 5, 10, 25, 50, 75],
    'Expected 7 canonical LMH25 cover comparison blocks',
  );

  for (const block of COVER_COMPARISON_BLOCKS) {
    assert.ok(block.patches.length > 0, `Block ${block.label} must contain at least one patch`);

    for (let i = 0; i < block.patches.length; i += 1) {
      const a = block.patches[i];
      assert.ok(a.w > 0 && a.h > 0, `Block ${block.label} patch ${i} must have positive size`);
      assert.ok(a.x >= 0 && a.x + a.w <= 100, `Block ${block.label} patch ${i} out of X bounds [0,100]`);
      assert.ok(a.y >= 0 && a.y + a.h <= 100, `Block ${block.label} patch ${i} out of Y bounds [0,100]`);

      for (let j = i + 1; j < block.patches.length; j += 1) {
        const b = block.patches[j];
        const overlapX = Math.min(a.x + a.w, b.x + b.w) - Math.max(a.x, b.x);
        const overlapY = Math.min(a.y + a.h, b.y + b.h) - Math.max(a.y, b.y);
        assert.ok(
          !(overlapX > 0 && overlapY > 0),
          `Block ${block.label} patches ${i} and ${j} overlap (${overlapX}x${overlapY})`,
        );
      }
    }

    const sumArea = block.patches.reduce((acc, r) => acc + r.w * r.h, 0);
    const unionArea = computeRectUnionArea(block.patches);
    const actualPercent = unionArea / 100;
    const errorPercent = Math.abs(actualPercent - block.percent);

    assert.ok(
      Math.abs(unionArea - sumArea) < 1e-6,
      `Block ${block.label} union area (${unionArea}) differs from sum (${sumArea})`,
    );
    assert.ok(
      errorPercent <= 0.05,
      `Block ${block.label} actual percent ${actualPercent}% deviates by ${errorPercent}% (> 0.05%)`,
    );
    assert.ok(
      Math.abs(unionArea - block.percent * 100) < 1e-6,
      `Block ${block.label} expected exact area ${block.percent * 100}, got ${unionArea}`,
    );
  }
});
