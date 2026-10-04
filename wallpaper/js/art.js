// 一池 · 网页壁纸 — 程序化纹理烘焙。鱼身、植物、波纹与反光按 macOS 版
// (Sources/FishArtwork.swift / PlantArtwork.swift / PondWater.swift) 的路径与
// 种子逐条移植：同种子 → 同形状，可与 Mac 渲染对照校色。
// 烘焙坐标系为 Y 向上（与 SpriteKit 一致）：bake() 内部翻转一次，
// 产出的位图即为正常观看方向，运行时再翻回世界坐标绘制。
'use strict';

// bounds: {x, y, w, h}（Y-up 局部坐标）；draw(ctx) 在 Y-up 空间作画。
function bake(bounds, scale, draw) {
  const w = Math.max(1, Math.ceil(bounds.w * scale));
  const h = Math.max(1, Math.ceil(bounds.h * scale));
  const canvas = document.createElement('canvas');
  canvas.width = w; canvas.height = h;
  const ctx = canvas.getContext('2d');
  ctx.translate(0, h); ctx.scale(scale, -scale);   // 翻到 Y-up
  ctx.translate(-bounds.x, -bounds.y);
  ctx.lineCap = 'round'; ctx.lineJoin = 'round';
  draw(ctx);
  canvas.bounds = bounds;
  return canvas;
}

function fillPath(ctx, path, hex, alpha = 1) {
  ctx.fillStyle = rgbCss(hex, alpha); ctx.fill(path);
}
function strokePath(ctx, path, hex, width = 1, alpha = 1) {
  ctx.strokeStyle = rgbCss(hex, alpha); ctx.lineWidth = width; ctx.stroke(path);
}

// 不规则有机轮廓（PondEnvironment.organic）。
function organic(center, radius, random, count = 18) {
  const points = [];
  for (let i = 0; i < count; i++) {
    const a = i / count * TAU, r = radius * random.range(0.78, 1.15);
    points.push({ x: center.x + Math.cos(a) * r, y: center.y + Math.sin(a) * r * 0.78 });
  }
  const p = new Path2D();
  const first = { x: (points[0].x + points[count - 1].x) / 2, y: (points[0].y + points[count - 1].y) / 2 };
  p.moveTo(first.x, first.y);
  for (let i = 0; i < count; i++) {
    const next = points[(i + 1) % count];
    p.quadraticCurveTo(points[i].x, points[i].y, (points[i].x + next.x) / 2, (points[i].y + next.y) / 2);
  }
  p.closePath();
  return p;
}

// ── 植物 ────────────────────────────────────────────────────────────────────
const PLANT_BOUNDS = {
  lotus:    { x: -120, y: -110, w: 240, h: 220 },
  lily:     { x: -120, y: -110, w: 240, h: 220 },
  flower:   { x: -78,  y: -74,  w: 156, h: 148 },
  reed:     { x: -140, y: -40,  w: 280, h: 320 },
  pondweed: { x: -140, y: -40,  w: 280, h: 320 },
  duckweed: { x: -50,  y: -40,  w: 100, h: 80 },
};
const plantArtCache = new Map();

function plantArt(kind, variant) {
  const key = KIND_ID[kind] * 10 + variant;
  if (plantArtCache.has(key)) return plantArtCache.get(key);
  const rng = new SeededRandom(57319 + key * 7919);
  const canvas = bake(PLANT_BOUNDS[kind], 3, ctx => {
    if (kind === 'lotus' || kind === 'lily') drawLeaf(ctx, kind === 'lily', variant, rng);
    else if (kind === 'flower') drawFlower(ctx, variant, rng);
    else if (kind === 'reed') drawReeds(ctx, rng);
    else if (kind === 'pondweed') drawPondweed(ctx, rng);
    else drawDuckweed(ctx, rng);
  });
  plantArtCache.set(key, canvas);
  return canvas;
}

function quadraticPoint(a, b, c, t) {
  const u = 1 - t;
  return { x: u * u * a.x + 2 * u * t * b.x + t * t * c.x, y: u * u * a.y + 2 * u * t * b.y + t * t * c.y };
}

function drawLeaf(ctx, lily, variant, random) {
  const rx = random.range(91, 103), ry = random.range(73, 88);
  const center = { x: lily ? -5 : 3, y: lily ? -15 : -3 };
  const start = lily ? 0.22 : 0.0, end = lily ? TAU - 0.22 : TAU;
  const edge = [];
  for (let i = 0; i <= 80; i++) {
    const a = start + (end - start) * i / 80;
    const r = 1 + 0.016 * Math.sin(a * 11 + variant) + 0.009 * Math.sin(a * 23) + 0.026 * Math.sin(a * 3 + 0.7);
    edge.push({ x: Math.cos(a) * rx * r, y: Math.sin(a) * ry * r });
  }
  const outline = new Path2D();
  if (lily) { outline.moveTo(center.x, center.y); outline.quadraticCurveTo(35, -7, edge[0].x, edge[0].y); }
  else outline.moveTo(edge[0].x, edge[0].y);
  for (const point of edge.slice(1)) outline.lineTo(point.x, point.y);
  if (lily) outline.quadraticCurveTo(38, -24, center.x, center.y);
  outline.closePath();

  ctx.save(); ctx.translate(3, -5);
  fillPath(ctx, outline, 0x16372A, 0.28); ctx.restore();
  const greens = lily ? [0x416846, 0x597A47, 0x4A7042, 0x6E854B] : [0x66834F, 0x557D4B, 0x7D9157, 0x4D7346];
  fillPath(ctx, outline, greens[variant % greens.length]);
  strokePath(ctx, outline, 0x233F2B, 0.8, 0.6);
  ctx.save(); ctx.clip(outline);
  for (let i = 0; i < 55; i++) {
    const at = { x: random.range(-rx, rx), y: random.range(-ry, ry) };
    const patch = organic(at, random.range(4, 17), random, 8);
    fillPath(ctx, patch, random.next() < 0.55 ? 0xBDD28A : 0x203D2A, random.range(0.025, 0.075));
  }
  const veinCount = lily ? 15 : 19;
  for (let i = 0; i < veinCount; i++) {
    const a = start + (end - start) * (i + 0.4) / veinCount;
    const tip = { x: Math.cos(a) * rx * 0.97, y: Math.sin(a) * ry * 0.97 };
    const bend = random.range(-0.12, 0.12);
    const middle = { x: center.x * 0.42 + Math.cos(a + bend) * rx * 0.52, y: center.y * 0.42 + Math.sin(a + bend) * ry * 0.52 };
    const vein = new Path2D();
    vein.moveTo(center.x, center.y); vein.quadraticCurveTo(middle.x, middle.y, tip.x, tip.y);
    strokePath(ctx, vein, 0x294B32, 1.65, 0.45);
    ctx.save(); ctx.translate(-0.45, 0.6);
    strokePath(ctx, vein, 0xC2CC89, 0.7, 0.67); ctx.restore();
    for (let branch = 1; branch <= 6; branch++) {
      const t = branch / 7;
      const root = quadraticPoint(center, middle, tip, t);
      for (const side of [-1, 1]) {
        const angle = a + side * 0.23 * (1 - t * 0.5);
        const outer = { x: Math.cos(angle) * rx * Math.min(0.97, t + 0.17), y: Math.sin(angle) * ry * Math.min(0.97, t + 0.17) };
        const control = { x: root.x + Math.cos(a + side * 0.8) * 12, y: root.y + Math.sin(a + side * 0.8) * 10 };
        const branchPath = new Path2D();
        branchPath.moveTo(root.x, root.y); branchPath.quadraticCurveTo(control.x, control.y, outer.x, outer.y);
        strokePath(ctx, branchPath, 0xB1C382, 0.42, 0.36);
        const fineRoot = quadraticPoint(root, control, outer, 0.58);
        const fine = new Path2D();
        fine.moveTo(fineRoot.x, fineRoot.y);
        fine.lineTo(fineRoot.x + Math.cos(a) * 6, fineRoot.y + Math.sin(a) * 5);
        strokePath(ctx, fine, 0xC4CB91, 0.25, 0.25);
      }
    }
  }
  for (let i = 0; i < 8; i++) {
    const a = random.range(start, end), b = a + random.range(0.12, 0.38);
    const rim = new Path2D();
    rim.moveTo(Math.cos(a) * rx * 0.97, Math.sin(a) * ry * 0.97);
    rim.quadraticCurveTo(Math.cos((a + b) / 2) * rx, Math.sin((a + b) / 2) * ry, Math.cos(b) * rx * 0.97, Math.sin(b) * ry * 0.97);
    strokePath(ctx, rim, i % 3 === 0 ? 0xB4A36C : 0xB2C385, random.range(0.6, 1.6), 0.6);
  }
  for (let i = 0; i < 750; i++) {
    const dot = random.range(0.18, 0.62);
    ctx.fillStyle = rgbCss(random.next() < 0.6 ? 0xD5D5A4 : 0x193D2B, random.range(0.06, 0.18));
    ctx.beginPath();
    ctx.ellipse(random.range(-rx, rx), random.range(-ry, ry), dot / 2, dot / 2, 0, 0, TAU);
    ctx.fill();
  }
  if (variant === 2 || variant === 3) {
    for (let i = 0; i < 5; i++) {
      const a = random.range(0, TAU), r = random.range(0.72, 0.94);
      fillPath(ctx, organic({ x: Math.cos(a) * rx * r, y: Math.sin(a) * ry * r }, random.range(1, 3), random, 6), 0xA29350, 0.65);
    }
  }
  if (!lily) {
    ctx.fillStyle = rgbCss(0xCDD39B, 0.8);
    ctx.beginPath();
    ctx.ellipse(center.x, center.y + 1.7 / 2, 2.2, 1.7, 0, 0, TAU);
    ctx.fill();
  }
  for (let i = 0; i < variant % 3 + 1; i++) {
    const x = random.range(-45, 48), y = random.range(-32, 40), r = random.range(1.8, 3.6);
    ctx.fillStyle = rgbCss(0x243F31, 0.75);
    ctx.beginPath(); ctx.ellipse(x, y - r * 0.8 - r * 0.75 + 0.8, r, r * 0.75, 0, 0, TAU); ctx.fill();
    ctx.fillStyle = rgbCss(0xDAE6CB, 0.7);
    ctx.beginPath(); ctx.ellipse(x, y + r * 0.25, r * 0.5, r * 0.25, 0, 0, TAU); ctx.fill();
  }
  ctx.restore();
}

function drawFlower(ctx, variant, random) {
  ctx.fillStyle = rgbCss(0x18372A, 0.27);
  ctx.beginPath(); ctx.ellipse(5, -2.5, 56, 45.5, 0, 0, TAU); ctx.fill();
  const ivory = variant % 2 === 1;
  for (let ring = 0; ring < 4; ring++) {
    const count = [10, 11, 9, 7][ring];
    const length = 62 - ring * 11;
    for (let i = 0; i < count; i++) {
      ctx.save();
      ctx.rotate(i / count * TAU + ring * 0.31 + random.range(-0.055, 0.055));
      ctx.scale(random.range(0.85, 1.05), random.range(0.9, 1.07));
      const petal = new Path2D();
      petal.moveTo(-3, 2);
      petal.bezierCurveTo(-length * 0.34, length * 0.38, -length * 0.2, length * 0.77, 3, length);
      petal.bezierCurveTo(length * 0.3, length * 0.72, length * 0.3, length * 0.25, 4, 2);
      petal.closePath();
      const pink = [0xB97587, 0xD393A2, 0xE7B7BF, 0xF1D7CD];
      const cream = [0xB2B898, 0xD5D5B6, 0xE5E1C8, 0xF4EBD3];
      fillPath(ctx, petal, ivory ? cream[ring] : pink[ring]);
      strokePath(ctx, petal, ivory ? 0x858E6C : 0x9D6174, 0.7, 0.7);
      const inner = new Path2D();
      inner.moveTo(3, 5);
      inner.quadraticCurveTo(-4, length * 0.6, 3, length);
      inner.quadraticCurveTo(13, length * 0.65, 7, 12);
      inner.closePath();
      fillPath(ctx, inner, ivory ? 0xFFF5DC : 0xFFE6DE, 0.38);
      for (let rib = -1; rib <= 1; rib++) {
        const ribPath = new Path2D();
        ribPath.moveTo(rib * 2, 9);
        ribPath.quadraticCurveTo(rib * 7, length * 0.55, 3 + rib * 3, length * 0.85);
        strokePath(ctx, ribPath, ivory ? 0x93996D : 0xA86882, 0.35, 0.32);
      }
      ctx.restore();
    }
  }
  for (let i = 0; i < 27; i++) {
    const a = i / 27 * TAU, r = random.range(9, 15);
    const spoke = new Path2D();
    spoke.moveTo(Math.cos(a) * 5, Math.sin(a) * 5);
    spoke.lineTo(Math.cos(a) * r, Math.sin(a) * r);
    strokePath(ctx, spoke, 0xC69C39, 1.1, 1);
    ctx.fillStyle = rgbCss(0xF4D87A);
    ctx.beginPath(); ctx.ellipse(Math.cos(a) * r, Math.sin(a) * r, 1, 1, 0, 0, TAU); ctx.fill();
  }
  ctx.fillStyle = rgbCss(0xD7BA5A);
  ctx.beginPath(); ctx.ellipse(0, 0, 6, 6, 0, 0, TAU); ctx.fill();
  for (let i = 0; i < 12; i++) {
    ctx.fillStyle = rgbCss(0x8D833C, 0.6);
    ctx.beginPath(); ctx.ellipse(random.range(-4, 4), random.range(-4, 4), 0.6, 0.6, 0, 0, TAU); ctx.fill();
  }
}

function drawReeds(ctx, random) {
  for (let i = 0; i < 9; i++) {
    const height = random.range(130, 262), bend = random.range(-102, 102), w = random.range(4, 9);
    const base = { x: random.range(-12, 12), y: random.range(-5, 9) };
    const tip = { x: bend, y: height };
    const first = { x: base.x + bend * 0.2 - 18, y: height * 0.3 };
    const second = { x: bend * 0.55 + 24, y: height * 0.84 };
    const blade = new Path2D();
    blade.moveTo(base.x, base.y);
    blade.bezierCurveTo(first.x, first.y, second.x, second.y, tip.x, tip.y);
    blade.bezierCurveTo(second.x + w * 0.7, second.y, first.x + w, first.y, base.x + w, base.y);
    blade.closePath();
    fillPath(ctx, blade, i % 3 === 0 ? 0x6B8C50 : i % 3 === 1 ? 0x3F6F48 : 0x527D49, 0.83);
    const spine = new Path2D();
    spine.moveTo(base.x + w * 0.45, base.y);
    spine.bezierCurveTo(first.x + w * 0.45, first.y, second.x, second.y, tip.x, tip.y);
    strokePath(ctx, spine, 0xACBA78, 0.7, 0.65);
    strokePath(ctx, blade, 0x254E38, 0.55, 0.5);
  }
}

function drawPondweed(ctx, random) {
  for (let stem = 0; stem < 4; stem++) {
    ctx.save(); ctx.rotate(stem * 0.23 - 0.35);
    const height = random.range(150, 235), bend = random.range(-30, 30);
    const stemPath = new Path2D();
    stemPath.moveTo(0, 0);
    stemPath.quadraticCurveTo(-24, height * 0.5, bend, height);
    strokePath(ctx, stemPath, 0x446B3D, 2.1, 0.8);
    for (let node = 1; node < 14; node++) {
      const t = node / 14;
      const root = quadraticPoint({ x: 0, y: 0 }, { x: -24, y: height * 0.5 }, { x: bend, y: height }, t);
      for (const side of [-1, 1]) {
        const l = random.range(15, 31) * (1.15 - t * 0.4);
        const tip = { x: root.x + side * l, y: root.y + random.range(10, 21) };
        const blade = new Path2D();
        blade.moveTo(root.x, root.y);
        blade.quadraticCurveTo(root.x + side * l * 0.9, root.y - 4, tip.x, tip.y);
        blade.quadraticCurveTo(root.x + side * l * 0.65, tip.y + 6, root.x, root.y);
        blade.closePath();
        fillPath(ctx, blade, node % 3 === 0 ? 0x718D51 : 0x4E7D4A, 0.88);
        const rib = new Path2D();
        rib.moveTo(root.x, root.y); rib.lineTo(tip.x, tip.y);
        strokePath(ctx, rib, 0xB0BD7C, 0.5, 0.6);
      }
    }
    ctx.restore();
  }
}

function drawDuckweed(ctx, random) {
  for (let i = 0; i < 16; i++) {
    const at = { x: random.range(-38, 38), y: random.range(-27, 27) }, r = random.range(2.5, 5.5);
    ctx.fillStyle = rgbCss(0x203F2E, 0.7);
    ctx.beginPath(); ctx.ellipse(at.x + 1, at.y - 1 - r * 0.225, r, r * 0.725, 0, 0, TAU); ctx.fill();
    ctx.fillStyle = rgbCss(random.next() < 0.5 ? 0x8CA65E : 0x6D924F);
    ctx.beginPath(); ctx.ellipse(at.x, at.y, r, r * 0.725, 0, 0, TAU); ctx.fill();
    const line = new Path2D();
    line.moveTo(at.x - r * 0.5, at.y - r * 0.2); line.lineTo(at.x + r * 0.5, at.y - r * 0.2);
    strokePath(ctx, line, 0xC1CF8B, 0.5, 0.6);
  }
}

// ── 水面纹理 ────────────────────────────────────────────────────────────────
let crestTexture = null;
function crestArt() {
  if (crestTexture) return crestTexture;
  crestTexture = bake({ x: -132, y: -132, w: 264, h: 264 }, 2, ctx => {
    const contour = new Path2D();
    for (let i = 0; i <= 192; i++) {
      const a = i / 192 * TAU;
      const r = 124 + Math.sin(a * 3 + 0.4) * 1.2 + Math.sin(a * 7) * 0.6;
      const x = Math.cos(a) * r, y = Math.sin(a) * r;
      if (i === 0) contour.moveTo(x, y); else contour.lineTo(x, y);
    }
    contour.closePath();
    ctx.save(); ctx.translate(0.6, -1.6);
    strokePath(ctx, contour, 0x183E37, 2.4, 0.55); ctx.restore();
    strokePath(ctx, contour, 0xD9E8D2, 1.6, 0.8);
    for (const [start, end] of [[0.25, 1.15], [1.5, 2.5], [3.5, 3.9], [5.3, 5.9]]) {
      const arc = new Path2D();
      arc.arc(0, 0, 124, start, end, false);
      strokePath(ctx, arc, 0xEEF2DA, 2.1, 0.8);
    }
  });
  return crestTexture;
}

let glintTextures = null;
function glintArts() {
  if (glintTextures) return glintTextures;
  glintTextures = [];
  for (let variant = 0; variant < 4; variant++) {
    const random = new SeededRandom(915871 + variant * 7919);
    glintTextures.push(bake({ x: 0, y: 0, w: 180, h: 48 }, 2, ctx => {
      for (let i = 0; i < 3; i++) {
        const x = random.range(12, 60), y = 12 + i * 10, w = random.range(28, 80);
        const curve = new Path2D();
        curve.moveTo(x, y);
        curve.bezierCurveTo(x + w * 0.28, y + 3, x + w * 0.64, y - 3, x + w, y + 1);
        strokePath(ctx, curve, 0xD5E6DE, random.range(0.7, 1.3), random.range(0.3, 0.6));
      }
    }));
  }
  return glintTextures;
}

// ── 金鱼 ────────────────────────────────────────────────────────────────────
function initialDesign(index) {
  const variant = index % 4;
  return {
    variant,
    bodyColor: variant === 1 ? 0xE8DDC4 : variant === 2 ? 0xCBA048 : 0xD97436,
    finColor: variant === 2 ? 0xDDBE70 : 0xE6A26A,
  };
}

function fishBodyPath() {
  const p = new Path2D();
  p.moveTo(41, 0);
  p.bezierCurveTo(40, 24, -12, 23, -31, 0);
  p.bezierCurveTo(-12, -23, 40, -24, 41, 0);
  p.closePath();
  return p;
}

const FISH_PART_BOUNDS = {
  body: { x: -34, y: -25, w: 79, h: 50 },
  tail: { x: -52, y: -32, w: 58, h: 64 },
  fin: { x: -27, y: -2, w: 32, h: 36 },
};
const fishCache = new Map();

function designKey(design) {
  return `${design.bodyColor.toString(16)}|${design.finColor.toString(16)}|${design.variant}`;
}

function fishParts(design) {
  const key = designKey(design);
  if (fishCache.has(key)) return fishCache.get(key);
  const parts = {
    body: bake(FISH_PART_BOUNDS.body, 4, ctx => drawFishBody(ctx, design)),
    tail: bake(FISH_PART_BOUNDS.tail, 4, ctx => drawFishTail(ctx, design)),
    finUp: bake(FISH_PART_BOUNDS.fin, 4, ctx => drawFishFin(ctx, design, 1)),
    finDown: bake(FISH_PART_BOUNDS.fin, 4, ctx => drawFishFin(ctx, design, -1)),
  };
  parts.shadow = bake(FISH_PART_BOUNDS.body, 4, ctx => {
    fillPath(ctx, fishBodyPath(), 0x08251D, 0.25);
  });
  if (fishCache.size > 24) fishCache.clear();
  fishCache.set(key, parts);
  return parts;
}

function drawFishBody(ctx, design) {
  const body = fishBodyPath();
  fillPath(ctx, body, design.bodyColor);
  ctx.save(); ctx.clip(body);
  if (design.variant === 1) {
    const patch = new Path2D();
    patch.moveTo(30, 14);
    patch.bezierCurveTo(-1, 18, 34, -11, 8, -17);
    patch.bezierCurveTo(-16, -20, -12, 15, 30, 14);
    patch.closePath();
    fillPath(ctx, patch, 0xC96B35);
    ctx.fillStyle = rgbCss(0xC96B35);
    ctx.beginPath(); ctx.ellipse(-12, -0.5, 10, 10.5, 0, 0, TAU); ctx.fill();
  } else if (design.variant === 3) {
    const patch = new Path2D();
    patch.moveTo(19, 17);
    patch.bezierCurveTo(-6, 24, 33, -15, 7, -18);
    patch.bezierCurveTo(-20, -17, 3, 10, -8, 17);
    patch.closePath();
    fillPath(ctx, patch, 0xE8DFCE);
  }
  const top = new Path2D();
  top.moveTo(-31, 0);
  top.bezierCurveTo(-10, -24, 35, -24, 40, -2);
  top.bezierCurveTo(26, -12, -4, -15, -31, 0);
  top.closePath();
  fillPath(ctx, top, 0x493527, 0.10);
  const random = new SeededRandom(71823);
  for (let i = 0; i < 100; i++) {
    const r = random.range(0.09, 0.3);
    ctx.fillStyle = rgbCss(0xFFF0CC, random.range(0.04, 0.16));
    ctx.beginPath();
    ctx.ellipse(random.range(-27, 37), random.range(-17, 17), r / 2, r / 2, 0, 0, TAU);
    ctx.fill();
  }
  for (let column = 0; column < 8; column++) {
    const x = column * 5.8 - 20;
    for (let row = -2; row <= 2; row++) {
      const y = row * 5.2 + (column % 2 === 0 ? 0 : 2.6);
      const dark = new Path2D();
      dark.moveTo(x, y - 2); dark.quadraticCurveTo(x - 3.7, y, x, y + 2);
      strokePath(ctx, dark, 0x765438, 0.42, 0.26);
      const light = new Path2D();
      light.moveTo(x + 0.7, y - 1.7); light.quadraticCurveTo(x - 2.6, y, x + 0.7, y + 1.7);
      strokePath(ctx, light, 0xFFF0C6, 0.35, 0.3);
    }
  }
  ctx.restore();
  strokePath(ctx, body, 0x6C4C35, 0.55, 0.65);
  const gill = new Path2D();
  gill.moveTo(23, -12); gill.quadraticCurveTo(17, 0, 23, 12);
  strokePath(ctx, gill, 0x835137, 0.65, 0.5);
  const belly = new Path2D();
  belly.moveTo(-18, 1); belly.quadraticCurveTo(-1, 4, 17, 1);
  strokePath(ctx, belly, 0xF1D7A6, 1.2, 0.4);
  for (const y of [-8.5, 8.5]) {
    ctx.fillStyle = rgbCss(0x3B3224);
    ctx.beginPath(); ctx.ellipse(31.9, y, 1.9, 1.65, 0, 0, TAU); ctx.fill();
    ctx.fillStyle = rgbCss(0xF9EBCF);
    ctx.beginPath(); ctx.ellipse(31.95, y - 0.2 + 0.45, 0.45, 0.45, 0, 0, TAU); ctx.fill();
  }
}

function drawFishTail(ctx, design) {
  const p = new Path2D();
  p.moveTo(0, 0);
  p.bezierCurveTo(-17, 5, -19, 30, -45, 28);
  p.bezierCurveTo(-54, 10, -40, 10, -32, 0);
  p.bezierCurveTo(-40, -10, -54, -10, -45, -28);
  p.bezierCurveTo(-19, -30, -17, -5, 0, 0);
  p.closePath();
  fillPath(ctx, p, design.finColor, 0.83);
  strokePath(ctx, p, 0x8B6343, 0.5, 0.45);
  for (let i = -5; i <= 5; i++) {
    const y = i * 5.2, x = -42 + 7 * (1 - Math.abs(i) / 5);
    const ray = new Path2D();
    ray.moveTo(0, 0); ray.quadraticCurveTo(-19, y * 0.25, x, y);
    strokePath(ctx, ray, 0x78593F, 0.35, 0.36);
  }
}

function drawFishFin(ctx, design, side) {
  const p = new Path2D();
  p.moveTo(0, 0);
  p.bezierCurveTo(-1, side * 20, -12, side * 30, -21, side * 24);
  p.quadraticCurveTo(-23, side * 6, 0, 0);
  p.closePath();
  fillPath(ctx, p, design.finColor, 0.67);
  strokePath(ctx, p, 0x765F3E, 0.45, 0.4);
  for (let i = 1; i <= 5; i++) {
    const ray = new Path2D();
    ray.moveTo(0, 0); ray.lineTo(-i * 3.5, side * (22 - i));
    strokePath(ctx, ray, 0x776242, 0.3, 0.36);
  }
}

// ── 时段染色：把纹理逐像素向时段色插值（等价 SKSpriteNode colorBlendFactor）。
const tintCache = new Map();
function tinted(texture, tintHex, factor) {
  if (factor <= 0) return texture;
  const key = texture.__id + '|' + tintHex + '|' + factor.toFixed(3);
  if (tintCache.has(key)) return tintCache.get(key);
  const out = document.createElement('canvas');
  out.width = texture.width; out.height = texture.height;
  const ctx = out.getContext('2d');
  ctx.drawImage(texture, 0, 0);
  const image = ctx.getImageData(0, 0, out.width, out.height);
  const [tr, tg, tb] = hexToRgb(tintHex);
  const data = image.data;
  for (let i = 0; i < data.length; i += 4) {
    if (data[i + 3] === 0) continue;
    data[i] = data[i] + (tr - data[i]) * factor;
    data[i + 1] = data[i + 1] + (tg - data[i + 1]) * factor;
    data[i + 2] = data[i + 2] + (tb - data[i + 2]) * factor;
  }
  ctx.putImageData(image, 0, 0);
  out.bounds = texture.bounds;
  if (tintCache.size > 160) tintCache.clear();
  tintCache.set(key, out);
  return out;
}

let textureId = 0;
function tagTexture(canvas) {
  if (canvas.__id === undefined) canvas.__id = ++textureId;
  return canvas;
}
