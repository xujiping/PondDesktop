// 一池 · 网页壁纸 — 模拟：鱼群运动学、光标意图流、涟漪与水面反光。
// 常数逐项来自 Sources/Pond.swift 的 Swimmer / CursorStream 与 PondWater.swift。
'use strict';

class Swimmer {
  constructor(x, y, angle, cruise, phase, length) {
    this.x = x; this.y = y; this.angle = angle; this.cruise = cruise;
    this.phase = phase; this.length = length;
    this.turn = 0;
    this.startledUntil = 0; this.startledFrom = { x: 0, y: 0 };
    this.meal = { x: 0, y: 0 }; this.hasMeal = false;
  }

  step(dt, time, width, height, speed, targets, positions, index, cursor, curious, cursorRadius) {
    let desired = this.angle + Math.sin(time * 0.37 + this.phase) * 0.45 + Math.sin(time * 0.17 + this.phase * 3) * 0.22;
    const margin = Math.min(150, Math.min(width, height) * 0.2);
    let fx = Math.cos(desired), fy = Math.sin(desired);
    if (this.x < margin) fx += (margin - this.x) / margin * 3.5;
    if (this.x > width - margin) fx -= (this.x - width + margin) / margin * 3.5;
    if (this.y < margin) fy += (margin - this.y) / margin * 3.5;
    if (this.y > height - margin) fy -= (this.y - height + margin) / margin * 3.5;
    for (let j = 0; j < positions.length; j++) {
      if (j === index) continue;
      const p = positions[j];
      const dx = this.x - p.x, dy = this.y - p.y, d2 = dx * dx + dy * dy;
      if (d2 > 1 && d2 < 85 * 85) {
        const d = Math.sqrt(d2);
        fx += dx / d * (1 - d / 85) * 0.7; fy += dy / d * (1 - d / 85) * 0.7;
      }
    }
    if (this.startledUntil > time) {
      const dx = this.x - this.startledFrom.x, dy = this.y - this.startledFrom.y;
      const d = Math.max(1, Math.hypot(dx, dy));
      fx += dx / d * 3.2; fy += dy / d * 3.2;
    } else if (curious && cursor) {
      // 光标像一根手指：游近了就停在旁边端详，不再贴上去。
      const dx = cursor.x - this.x, dy = cursor.y - this.y, distance = Math.hypot(dx, dy);
      if (distance > 70 && distance < cursorRadius) {
        fx += dx / distance * 0.8; fy += dy / distance * 0.8;
      }
    }
    // 食物：认准最近一处，半途不轻易换食；离得越远冲得越猛。
    let dashing = false;
    let nearestDistance = Infinity;
    if (targets.length > 0) {
      let nearest = targets[0];
      for (const spot of targets) {
        const d = Math.hypot(spot.x - this.x, spot.y - this.y);
        if (d < nearestDistance) { nearestDistance = d; nearest = spot; }
      }
      if (this.hasMeal) {
        for (const spot of targets) {
          if (Math.hypot(spot.x - this.meal.x, spot.y - this.meal.y) < 1) {
            const d = Math.hypot(spot.x - this.x, spot.y - this.y);
            if (d < nearestDistance * 1.25) { nearest = spot; nearestDistance = d; }
            break;
          }
        }
      }
      this.meal = nearest; this.hasMeal = true;
      if (nearestDistance > 16) {
        const urgency = nearestDistance > 110 ? 4.5 : 3.2;
        const dx = nearest.x - this.x, dy = nearest.y - this.y;
        fx += dx / nearestDistance * urgency; fy += dy / nearestDistance * urgency;
        dashing = nearestDistance > 60;
      }
    } else this.hasMeal = false;
    desired = Math.atan2(fy, fx);
    const delta = Math.atan2(Math.sin(desired - this.angle), Math.cos(desired - this.angle));
    // 受惊急转急游，抢食利落转向，平时平缓。
    const panicking = this.startledUntil > time;
    const gain = panicking ? 3.4 : dashing ? 3.0 : 1.9;
    const turnLimit = panicking ? 2.2 : dashing ? 2.0 : 1.05;
    this.turn += (clamp(delta * gain, -turnLimit, turnLimit) - this.turn) * Math.min(1, dt * (panicking ? 6 : dashing ? 5.5 : 3));
    this.angle += this.turn * dt;
    let boost = 1;
    if (panicking) {
      const left = clamp((this.startledUntil - time) / 1.4, 0, 1);
      boost = 1 + 6 * left * left;
    } else if (dashing) {
      boost = 1 + 2.2 * clamp((nearestDistance - 60) / 180, 0, 1);
    }
    const velocity = this.cruise * speed * boost * (1 + 0.12 * Math.sin(time * 1.1 + this.phase));
    this.x = clamp(this.x + Math.cos(this.angle) * velocity * dt, 28, Math.max(28, width - 28));
    this.y = clamp(this.y + Math.sin(this.angle) * velocity * dt, 28, Math.max(28, height - 28));
  }
}

// 把原始鼠标采样整理成池塘意图：缓动涟漪、急挥惊吓、桌面轻点。
class CursorStream {
  constructor() {
    this.speed = 0;
    this.last = null; this.lastTime = 0;
    this.ripple = null;
    this.startleCooldown = -1;
    this.tap = null;
  }
  static get calmSpeed() { return 240; }
  static get startleSpeed() { return 800; }
  // 缓动时按路程与时间双重节流地吐出涟漪位置；急动不出涟漪。
  moved(p, t) {
    if (this.last && t > this.lastTime) {
      this.speed = this.speed * 0.6 + Math.hypot(p.x - this.last.x, p.y - this.last.y) / (t - this.lastTime) * 0.4;
    }
    this.last = p; this.lastTime = t;
    if (this.speed >= CursorStream.calmSpeed) return null;
    if (this.ripple && (t - this.ripple.time < 0.13 || Math.hypot(p.x - this.ripple.point.x, p.y - this.ripple.point.y) < 26)) return null;
    this.ripple = { point: p, time: t };
    return p;
  }
  // 一次急挥只惊吓一次，0.6 秒内不重复触发。
  startled(t) {
    if (this.speed > CursorStream.startleSpeed && t > this.startleCooldown) {
      this.startleCooldown = t + 0.6;
      return true;
    }
    return false;
  }
  pressed(p, t) { this.tap = { point: p, time: t, anchor: p }; }
  dragged(p) {
    if (this.tap && Math.hypot(p.x - this.tap.anchor.x, p.y - this.tap.anchor.y) > 6) this.tap = null;
  }
  released(t) {
    if (!this.tap) return null;
    const held = this.tap;
    this.tap = null;
    return t - held.time < 0.35 ? held.point : null;
  }
}

class WaterRipple {
  constructor(x, y, time, radius, strength, reducedMotion) {
    this.x = x; this.y = y; this.born = time;
    this.lifetime = reducedMotion ? 2 : 5.6;
    this.radius = radius; this.strength = strength;
    const ringCount = reducedMotion ? 1 : strength < 0.3 ? 2 : 4;
    this.rings = [];
    for (let i = 0; i < ringCount; i++) this.rings.push({ delay: i * 0.32, visible: false, r: 0, alpha: 0 });
    this.advance(time);
  }
  advance(time) {
    const age = time - this.born;
    for (const ring of this.rings) {
      const progress = (age - ring.delay) / this.lifetime;
      ring.visible = progress >= 0 && progress < 1;
      if (!ring.visible) continue;
      ring.r = 9 + this.radius * Math.pow(progress, 0.82);
      ring.alpha = this.strength * Math.min(1, progress * 16) * Math.pow(1 - progress, 1.4) * (1 - this.rings.indexOf(ring) * 0.14);
    }
    return age < this.lifetime + (this.rings.length - 1) * 0.32;
  }
}

// 稀疏反光：各自缓慢漂移、变淡，位置不铺满全屏。
class WaterGlint {
  constructor(texture, anchor, phase, distance, daylight) {
    this.anchor = anchor; this.phase = phase; this.distance = distance;
    this.texture = daylight.glintBlend > 0 ? tinted(tagTexture(texture), daylight.glow, daylight.glintBlend) : texture;
    this.alphaScale = daylight.glowAlpha;
    this.x = anchor.x; this.y = anchor.y; this.rotation = 0; this.alpha = 0;
    this.update(0);
  }
  update(time) {
    const t = time * 0.23 + this.phase;
    this.x = this.anchor.x + Math.sin(t * 0.7) * 9 * this.distance;
    this.y = this.anchor.y + Math.sin(t * 0.83 + 1) * 4 * this.distance;
    this.rotation = Math.sin(t * 0.6) * 0.035;
    this.alpha = (0.055 + 0.085 * Math.pow((Math.sin(t) + 1) / 2, 3)) * this.alphaScale;
  }
}
