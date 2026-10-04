// 一池 · 网页壁纸 — 池底与植物群落布局（Sources/PondEnvironment.swift 移植）。
// 同样的种子与调用顺序：群落位置、浮叶分布、卵石与泥斑和 macOS 版完全一致。
'use strict';

const KIND_ID = { lotus: 0, lily: 1, flower: 2, reed: 3, pondweed: 4, duckweed: 5 };

function plantUnit(size) { return clamp(Math.min(size.width, size.height) / 1150, 0.7, 1.65); }

function clusters(size) {
  const unit = plantUnit(size);
  const specs = [
    [0.075, 0.16, 170, 8, false],
    [0.91, 0.85, 175, 9, false],
    [0.94, 0.08, 145, 6, false],
    [0.025, 0.67, 145, 6, false],
    [0.57, 0.96, 115, 4, false],
    [0.29, 0.66, 102, 4, true],
    [0.51, 0.23, 105, 4, true],
    [0.73, 0.51, 110, 5, true],
  ];
  return specs.map(([x, y, spread, leaves, interior]) => ({
    center: { x: size.width * x, y: size.height * y },
    spread: spread * unit, leafCount: leaves, interior,
  }));
}

function placements(size, density) {
  const unit = plantUnit(size);
  const result = [];
  clusters(size).forEach((cluster, index) => {
    // 每个群落独立种子：改丰茂度不挪动已有植物。
    let rng = new SeededRandom(395177 + index * 104729);
    const submergedCount = Math.floor((cluster.interior ? 5 : 9) * density);
    for (let i = 0; i < submergedCount; i++) {
      const a = rng.range(0, TAU), d = rng.range(15, cluster.spread * 1.05);
      result.push({
        kind: i % 3 === 0 ? 'pondweed' : 'reed', variant: i % 4,
        position: { x: cluster.center.x + Math.cos(a) * d, y: cluster.center.y + Math.sin(a) * d * 0.8 },
        scale: rng.range(0.65, 1.02) * unit, rotation: rng.range(-2.8, 2.8),
        submerged: true, order: i * 0.01,
      });
    }
    rng = new SeededRandom(582391 + index * 7919);
    const leafCount = Math.max(2, Math.floor(cluster.leafCount * density));
    for (let i = 0; i < leafCount; i++) {
      const a = rng.range(0, TAU), d = Math.sqrt(rng.next()) * cluster.spread;
      const scale = rng.range(0.70, 1.08) * unit * (i % 5 === 3 ? 0.72 : 1);
      result.push({
        kind: (i + index) % 3 === 0 ? 'lotus' : 'lily', variant: (i + index) % 4,
        position: { x: cluster.center.x + Math.cos(a) * d, y: cluster.center.y + Math.sin(a) * d * 0.78 },
        scale, rotation: rng.range(0, TAU), submerged: false, order: i * 0.01,
      });
    }
    // 花开在叶群上方的空档，不被后画的叶子盖住。
    rng = new SeededRandom(85711 + index * 3571);
    const flowers = cluster.interior ? (index === 6 ? 1 : 0) : (index === 1 ? 2 : 1);
    for (let i = 0; i < flowers; i++) {
      result.push({
        kind: 'flower', variant: (index + i) % 4,
        position: { x: cluster.center.x + rng.range(-0.48, 0.48) * cluster.spread, y: cluster.center.y + rng.range(-0.4, 0.4) * cluster.spread },
        scale: rng.range(0.68, 0.85) * unit, rotation: rng.range(0, TAU), submerged: false, order: 2,
      });
    }
    const duckweedCount = Math.max(1, Math.floor((cluster.interior ? 2 : 4) * density));
    for (let i = 0; i < duckweedCount; i++) {
      const a = rng.range(0, TAU), d = rng.range(cluster.spread * 0.85, cluster.spread * 1.45);
      result.push({
        kind: 'duckweed', variant: i % 4,
        position: { x: cluster.center.x + Math.cos(a) * d, y: cluster.center.y + Math.sin(a) * d * 0.8 },
        scale: rng.range(0.75, 1.05) * unit, rotation: rng.range(0, TAU), submerged: false, order: 1,
      });
    }
  });
  return result;
}

function drawPebble(ctx, center, radius, random, daylight, alpha) {
  const p = organic(center, radius, random, 9);
  ctx.save(); ctx.translate(2, -2);
  fillPath(ctx, p, daylightApply(daylight, 0x183D32), alpha * 0.6); ctx.restore();
  const shades = [0x849181, 0x6D8171, 0xA5A28A, 0x5E7469, 0x8C8B72].map(h => daylightApply(daylight, h));
  fillPath(ctx, p, shades[Math.floor(random.range(0, 4.99))], alpha);
  const gleam = new Path2D();
  gleam.moveTo(center.x - radius * 0.5, center.y + radius * 0.36);
  gleam.quadraticCurveTo(center.x, center.y + radius * 0.68, center.x + radius * 0.45, center.y + radius * 0.36);
  strokePath(ctx, gleam, daylightApply(daylight, 0xD8CFAB), Math.max(0.45, radius / 12), alpha * 0.4);
}

// 烘焙整块池底：水色打底 + 泥斑 + 细颗粒 + 卵石 + 水光线条，一次性画完缓存。
function makeBed(size, density, palette, daylight, rasterScale) {
  const scale = Math.min(rasterScale, 4096 / Math.max(size.width, size.height));
  return bake({ x: 0, y: 0, w: size.width, h: size.height }, scale, ctx => {
    ctx.fillStyle = rgbCss(palette.water);
    ctx.fillRect(0, 0, size.width, size.height);
    let rng = new SeededRandom(182954);
    for (let i = 0; i < 210; i++) {
      const center = { x: rng.range(0, size.width), y: rng.range(0, size.height) };
      const r = rng.range(16, 125);
      fillPath(ctx, organic(center, r, rng), rng.next() < 0.5 ? palette.silt : daylightApply(daylight, 0x273F30), rng.range(0.025, 0.065));
    }
    const grains = Math.min(75000, Math.floor(size.width * size.height / 42));
    for (let i = 0; i < grains; i++) {
      const r = rng.range(0.25, 1.05);
      ctx.fillStyle = rgbCss(daylightApply(daylight, rng.next() < 0.58 ? 0xBDBDA1 : 0x213F31), rng.range(0.04, 0.15));
      ctx.fillRect(rng.range(0, size.width), rng.range(0, size.height), r, r * 0.7);
    }
    for (let i = 0; i < 480; i++) {
      drawPebble(ctx, { x: rng.range(0, size.width), y: rng.range(0, size.height) }, rng.range(1.2, 7), rng, daylight, 0.32);
    }
    for (const cluster of clusters(size)) {
      const pebbles = Math.floor((cluster.interior ? 13 : 27) * density);
      for (let i = 0; i < pebbles; i++) {
        const a = rng.range(0, TAU), d = rng.range(0, cluster.spread * 1.1);
        drawPebble(ctx, { x: cluster.center.x + Math.cos(a) * d, y: cluster.center.y + Math.sin(a) * d * 0.72 },
          rng.range(4, 14) * plantUnit(size), rng, daylight, 0.44);
      }
    }
    for (let i = 0; i < 26; i++) {
      const x = rng.range(0, size.width), y = rng.range(0, size.height), w = rng.range(55, 180);
      const streak = new Path2D();
      streak.moveTo(x, y);
      streak.bezierCurveTo(x + w * 0.3, y + 35, x + w * 0.55, y - 35, x + w, y + 18);
      strokePath(ctx, streak, daylightApply(daylight, 0xD3D8AB), 0.8, 0.07);
    }
  });
}
