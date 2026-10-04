// 一池 · 网页壁纸 — 基础库：确定性随机、色彩与时段光色。
// 随机数与种子和 macOS 版 (Sources/Pond.swift) 逐位一致，
// 保证底图、植物群落与鱼群初始布局跨平台完全相同。
'use strict';

const TAU = Math.PI * 2;

function clamp(v, lo, hi) { return Math.min(hi, Math.max(lo, v)); }

class SeededRandom {
  constructor(state = 84721) { this.state = BigInt(state); }
  next() {
    // 2862933555777941757 * state + 3037000493 (mod 2^64)，取高 53 位成 [0,1)。
    this.state = (2862933555777941757n * this.state + 3037000493n) & 0xffffffffffffffffn;
    return Number(this.state >> 11n) / Number(1n << 53n);
  }
  range(lo, hi) { return lo + this.next() * (hi - lo); }
}

function hexToRgb(hex) { return [(hex >> 16) & 255, (hex >> 8) & 255, hex & 255]; }
function lum(hex) { const [r, g, b] = hexToRgb(hex); return 0.2126 * r + 0.7152 * g + 0.0722 * b; }
function rgbCss(hex, alpha = 1) {
  const [r, g, b] = hexToRgb(hex);
  return alpha >= 1 ? `rgb(${r},${g},${b})` : `rgba(${r},${g},${b},${alpha})`;
}
// 线性插值两个 0xRRGGBB；t<=0 时返回原色（与 Swift blend 一致）。
function blend(a, b, t) {
  if (t <= 0) return a;
  const k = clamp(t, 0, 1);
  const av = hexToRgb(a), bv = hexToRgb(b);
  const out = av.map((v, i) => Math.round(v + (bv[i] - v) * k));
  return (out[0] << 16) | (out[1] << 8) | out[2];
}

// 一天的四个时段光色（Sources/Daylight.swift）。
const DAYLIGHTS = {
  dawn:  { key: 'dawn',  name: '凌晨', tint: 0x4A5A80, strength: 0.30, dim: 0.18, glow: 0xD6DFF0, glowAlpha: 0.6,  glintBlend: 0.45 },
  noon:  { key: 'noon',  name: '中午', tint: 0x385E50, strength: 0,    dim: 0,    glow: 0xFFF6D8, glowAlpha: 1,    glintBlend: 0 },
  dusk:  { key: 'dusk',  name: '傍晚', tint: 0x9A6238, strength: 0.26, dim: 0.16, glow: 0xFFC97E, glowAlpha: 1.15, glintBlend: 0.55 },
  night: { key: 'night', name: '晚上', tint: 0x14304A, strength: 0.42, dim: 0.34, glow: 0xAFC6E8, glowAlpha: 0.5,  glintBlend: 0.5 },
};

function effectiveDaylight(mode, date = now()) {
  if (mode !== 'auto' && DAYLIGHTS[mode]) return DAYLIGHTS[mode];
  const hour = date.getHours();
  if (hour >= 4 && hour < 11) return DAYLIGHTS.dawn;
  if (hour >= 11 && hour < 17) return DAYLIGHTS.noon;
  if (hour >= 17 && hour < 20) return DAYLIGHTS.dusk;
  return DAYLIGHTS.night;
}

// 测试钩子：?clock=23 可把“当前时间”固定到某小时，验证自动时段切换。
let clockHourOverride = null;
function setClockHour(hour) { clockHourOverride = hour; }
function now() {
  if (clockHourOverride === null) return new Date();
  const date = new Date();
  date.setHours(clockHourOverride, 0, 0, 0);
  return date;
}

// 先压暗再上时段色。
function daylightApply(daylight, hex) { return blend(blend(hex, 0x0A1712, daylight.dim), daylight.tint, daylight.strength); }

// 水色主题调色板（Sources/Pond.swift Palette）。
function paletteFor(theme, daylight) {
  const base = theme === 'ink'
    ? { water: 0x173D40, silt: 0x28504C, pebble: 0x59716A, leaf: 0x506E45 }
    : theme === 'blue'
      ? { water: 0x3B727C, silt: 0x4D8184, pebble: 0x82998B, leaf: 0x527F53 }
      : { water: 0x385E50, silt: 0x737F59, pebble: 0x7D9280, leaf: 0x557340 };
  const out = {};
  for (const k of Object.keys(base)) out[k] = daylightApply(daylight, base[k]);
  return out;
}
