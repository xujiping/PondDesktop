// 一池 · 网页壁纸 — 场景编排：相机、图层、渲染循环与宿主集成
// (Wallpaper Engine / Lively Wallpaper / 普通浏览器)。
// 图层顺序对应 SpriteKit 的 zPosition：
// 池底(-10) < 沉水草 < 金鱼(0) < 反光(-2@surface) < 涟漪(-1@surface) < 浮叶/浮萍/花 < 饲料(12)。
'use strict';

function drawTex(ctx, tex, lx, ly, w, h) {
  // lx/ly 为当前局部坐标系（Y 向上）里的左下角；位图正常方向绘制。
  ctx.save();
  ctx.translate(lx, ly + h);
  ctx.scale(1, -1);
  ctx.drawImage(tex, 0, 0, tex.width, tex.height, 0, 0, w, h);
  ctx.restore();
}
function drawTexC(ctx, tex, cx, cy, w, h) {
  drawTex(ctx, tex, cx - w / 2, cy - h / 2, w, h);
}

const DEFAULT_SETTINGS = {
  theme: 'jade',          // jade 青池 / ink 墨池 / blue 晴池
  fishCount: 24,
  swimSpeed: 0.8,
  viewDistance: 1.65,
  plantDensity: 1.15,
  daylightMode: 'auto',   // auto/dawn/noon/dusk/night
  mouseInteraction: true,
  feedMode: 'alt',        // alt/ctrl/shift/none
  lowPower: false,
};

class PondApp {
  constructor(canvas, settings) {
    this.canvas = canvas;
    this.ctx = canvas.getContext('2d');
    this.settings = settings;
    this.swimmers = [];
    this.placements = [];
    this.motions = [];
    this.foodSpots = [];
    this.crumbs = [];
    this.ripples = [];
    this.glints = [];
    this.designCache = [];
    this.rng = new SeededRandom();
    this.simTime = 0;
    this.daylight = effectiveDaylight(settings.daylightMode);
    this.floorStamp = '';
    this.configuredW = 0; this.configuredH = 0;
    this.wakeClock = 0; this.wakeIndex = 0;
    this.cursor = null;
    this.reducedMotion = matchMedia('(prefers-reduced-motion: reduce)').matches;
    this.cssW = 1; this.cssH = 1; this.dpr = 1;
  }

  get worldW() { return this.cssW * this.settings.viewDistance; }
  get worldH() { return this.cssH * this.settings.viewDistance; }

  resize() {
    this.cssW = Math.max(1, window.innerWidth);
    this.cssH = Math.max(1, window.innerHeight);
    this.dpr = Math.min(window.devicePixelRatio || 1, 2);
    this.canvas.width = Math.round(this.cssW * this.dpr);
    this.canvas.height = Math.round(this.cssH * this.dpr);
    this.configure();
  }

  // 设置变更后的整体重配：底图按签名重建，鱼群与涟漪尽量保留。
  configure() {
    const s = this.settings;
    const daylight = effectiveDaylight(s.daylightMode);
    const daylightChanged = this.daylight.key !== daylight.key;
    this.daylight = daylight;
    this.palette = paletteFor(s.theme, daylight);
    this.canvas.style.background = rgbCss(this.palette.water);
    const worldW = this.worldW, worldH = this.worldH;
    if (worldW <= 56 || worldH <= 56) return;

    // 视野变化时按比例迁移鱼与饲料，不重新随机。
    if (this.configuredW > 0 && (this.configuredW !== worldW || this.configuredH !== worldH)) {
      const xRatio = worldW / this.configuredW, yRatio = worldH / this.configuredH;
      for (const swimmer of this.swimmers) { swimmer.x *= xRatio; swimmer.y *= yRatio; }
      for (const spot of this.foodSpots) { spot.x *= xRatio; spot.y *= yRatio; }
      for (const crumb of this.crumbs) { crumb.x *= xRatio; crumb.y *= yRatio; }
    }
    this.configuredW = worldW; this.configuredH = worldH;

    // 底图只在主题/时段/丰茂度/尺寸/视野档变化时重烘焙。
    const rasterScale = this.dpr / s.viewDistance;
    const stamp = `${s.theme}|${daylight.key}|${Math.round(s.plantDensity * 10)}|${Math.round(this.cssW)}x${Math.round(this.cssH)}|${Math.round(s.viewDistance * 8)}|${rasterScale.toFixed(2)}`;
    if (stamp !== this.floorStamp || daylightChanged) {
      this.floorStamp = stamp;
      this.buildFloor(rasterScale);
      this.glints = [];
      const screenArea = this.cssW * this.cssH;
      const count = Math.min(12, Math.max(4, Math.floor(screenArea / 145000)));
      const random = new SeededRandom(871493);
      const arts = glintArts();
      for (let i = 0; i < count; i++) {
        this.glints.push(new WaterGlint(arts[i % 4],
          { x: random.range(0.08, 0.92) * worldW, y: random.range(0.08, 0.92) * worldH },
          random.range(0, TAU), s.viewDistance, daylight));
      }
      this.ripples = [];   // 改视野时清掉旧坐标里的波纹
    }

    // 鱼群数量：只增删尾部，随机流不回卷，与 macOS 版一致。
    const target = Math.round(s.fishCount);
    while (this.swimmers.length > target) this.swimmers.pop();
    while (this.swimmers.length < target) {
      const length = this.rng.range(74, 123);
      this.swimmers.push(new Swimmer(
        this.rng.range(80, Math.max(81, worldW - 80)),
        this.rng.range(80, Math.max(81, worldH - 80)),
        this.rng.range(0, TAU), this.rng.range(24, 48), this.rng.range(0, TAU), length));
    }
  }

  buildFloor(rasterScale) {
    const s = this.settings;
    this.bed = makeBed({ width: this.worldW, height: this.worldH }, s.plantDensity, this.palette, this.daylight, rasterScale);
    this.placements = placements({ width: this.worldW, height: this.worldH }, s.plantDensity);
    this.motions = this.placements.map(p => ({
      phase: (p.position.x * 0.037 + p.position.y * 0.023 + p.variant * 1.7) % TAU,
    }));
  }

  worldFromScreen(sx, sy) {
    return {
      x: (sx - this.cssW / 2) * this.settings.viewDistance + this.worldW / 2,
      y: (this.cssH / 2 - sy) * this.settings.viewDistance + this.worldH / 2,
    };
  }

  startle(near) {
    const radius = Math.min(this.worldW, this.worldH) * 0.28;
    for (const swimmer of this.swimmers) {
      if (Math.hypot(swimmer.x - near.x, swimmer.y - near.y) < radius) {
        swimmer.startledUntil = this.simTime + 1.4;
        swimmer.startledFrom = near;
      }
    }
  }

  addRipple(x, y, strength = 0.62, radius = 185) {
    if (this.ripples.length >= 20) this.ripples.shift();
    this.ripples.push(new WaterRipple(x, y, this.simTime, radius * this.settings.viewDistance, strength, this.reducedMotion));
  }

  feed(at) {
    const worldW = this.worldW, worldH = this.worldH;
    const center = at || {
      x: this.rng.range(worldW * 0.25, worldW * 0.75),
      y: this.rng.range(worldH * 0.25, worldH * 0.75),
    };
    this.foodSpots.push({ x: center.x, y: center.y, expiry: this.simTime + 16 });
    if (this.foodSpots.length > 5) this.foodSpots.shift();
    for (let i = 0; i < 16; i++) {
      this.crumbs.push({
        x: center.x + this.rng.range(-24, 24),
        y: center.y + this.rng.range(-24, 24),
        born: this.simTime, life: this.rng.range(7, 14),
      });
    }
    this.addRipple(center.x, center.y);
  }

  // 最近三处涟漪对某点的推挤（浮叶被涟漪轻推）。
  rippleDisplacement(x, y, time) {
    if (this.reducedMotion) return { x: 0, y: 0 };
    let ox = 0, oy = 0;
    const d0 = this.settings.viewDistance;
    for (const ripple of this.ripples.slice(-3)) {
      const dx = (x - ripple.x) / d0, dy = (y - ripple.y) / d0;
      const d = Math.max(1, Math.hypot(dx, dy)), age = time - ripple.born;
      const front = d - (9 + age * 37);
      const band = Math.max(0, 1 - Math.abs(front) / 32);
      const amount = Math.sin(front * 0.19) * band * ripple.strength * Math.max(0, 1 - age / ripple.lifetime) * 3 * d0;
      ox += dx / d * amount; oy += dy / d * amount;
    }
    return { x: ox, y: oy };
  }

  update(dt) {
    const s = this.settings;
    this.simTime += dt;
    const worldW = this.worldW, worldH = this.worldH;
    if (worldW <= 56 || worldH <= 56) return;

    for (const glint of this.glints) glint.update(this.simTime);
    this.ripples = this.ripples.filter(r => r.advance(this.simTime));
    this.foodSpots = this.foodSpots.filter(spot => this.simTime <= spot.expiry);
    this.crumbs = this.crumbs.filter(c => this.simTime - c.born < c.life + 2);

    // 光标在场 6 秒内才算数；静止或缓动让附近金鱼好奇。
    let cursorPoint = null, curious = false;
    if (s.mouseInteraction && this.cursor) {
      const age = this.simTime - this.cursor.time;
      if (age < 6) {
        cursorPoint = this.cursor.world;
        curious = this.cursor.speed < CursorStream.calmSpeed || age > 0.3;
      }
    }
    const cursorRadius = Math.min(worldW, worldH) * 0.35;
    const targets = this.foodSpots.map(spot => ({ x: spot.x, y: spot.y }));
    const positions = this.swimmers.map(f => ({ x: f.x, y: f.y }));
    for (let i = 0; i < this.swimmers.length; i++) {
      this.swimmers[i].step(dt, this.simTime, worldW, worldH, s.swimSpeed, targets, positions, i, cursorPoint, curious, cursorRadius);
    }

    // 浅水中的鱼偶尔带动水面，保持稀疏尾波。
    this.wakeClock += dt;
    if (!this.reducedMotion && this.wakeClock > 2.4 && this.swimmers.length) {
      this.wakeClock = 0;
      this.wakeIndex = (this.wakeIndex + 7) % this.swimmers.length;
      const fish = this.swimmers[this.wakeIndex];
      this.addRipple(fish.x - Math.cos(fish.angle) * fish.length * 0.4,
        fish.y - Math.sin(fish.angle) * fish.length * 0.4, 0.16, 72);
    }
  }

  // ── 渲染 ───────────────────────────────────────────────────────────────
  render() {
    const ctx = this.ctx;
    const s = this.settings;
    const worldW = this.worldW, worldH = this.worldH, d = s.viewDistance;
    ctx.setTransform(this.dpr, 0, 0, this.dpr, 0, 0);
    ctx.fillStyle = rgbCss(this.palette.water);
    ctx.fillRect(0, 0, this.cssW, this.cssH);
    if (worldW <= 56 || worldH <= 56 || !this.bed) return;

    ctx.save();
    ctx.translate(this.cssW / 2, this.cssH / 2);
    ctx.scale(1 / d, -1 / d);
    ctx.translate(-worldW / 2, -worldH / 2);
    ctx.imageSmoothingEnabled = true;

    this.drawBed(ctx);
    this.drawSubmerged(ctx);
    this.drawFish(ctx);
    this.drawGlints(ctx);
    this.drawRipples(ctx);
    this.drawSurfacePlants(ctx);
    this.drawCrumbs(ctx);

    ctx.restore();
  }

  // 池底轻微折射：横条平移近似着色器的水平位移（环境波动 + 涟漪波前）。
  drawBed(ctx) {
    const t = this.simTime % 3600;
    const worldW = this.worldW, worldH = this.worldH, d = this.settings.viewDistance;
    const bed = this.bed;
    const strips = this.reducedMotion ? 1 : clamp(Math.round(this.cssH / 6), 60, 200);
    const stripH = worldH / strips;
    const recent = this.ripples.slice(-3);
    for (let i = 0; i < strips; i++) {
      const y1 = worldH - i * stripH, y0 = y1 - stripH;
      let shiftX = 0;
      if (strips > 1) {
        const sy = this.cssH / 2 - ((y0 + y1) / 2 - worldH / 2) / d;
        const sx = this.cssW / 2;
        shiftX = 0.85 * (Math.sin(sy * 0.027 + t * 0.72) + Math.sin((sx + sy) * 0.014 - t * 0.49));
        for (const ripple of recent) {
          const dx = sx - (this.cssW / 2 + (ripple.x - worldW / 2) / d);
          const dy = sy - (this.cssH / 2 - (ripple.y - worldH / 2) / d);
          const dist = Math.max(1, Math.hypot(dx, dy));
          const age = this.simTime - ripple.born;
          const front = dist - (9 + age * 37);
          const band = Math.max(0, 1 - Math.abs(front) / 32);
          shiftX += dx / dist * Math.sin(front * 0.19) * band * ripple.strength * Math.max(0, 1 - age / ripple.lifetime) * 5;
        }
      }
      const srcY = bed.height * (1 - y1 / worldH);
      const srcH = Math.max(1, bed.height * stripH / worldH);
      ctx.save();
      ctx.translate(shiftX * d, y1);
      ctx.scale(1, -1);
      ctx.drawImage(bed, 0, srcY, bed.width, srcH, 0, 0, worldW, stripH + 0.6);
      ctx.restore();
    }
  }

  drawSubmerged(ctx) {
    const time = this.simTime, d = this.settings.viewDistance;
    const rows = [0, 0.125, 0.4167, 0.7083, 1];
    const bounds = PLANT_BOUNDS.reed;
    for (let i = 0; i < this.placements.length; i++) {
      const p = this.placements[i];
      if (!p.submerged) continue;
      const motion = this.motions[i];
      const shared = time * 0.34 + p.position.x / (720 * d) + p.position.y / (580 * d);
      const local = time * 0.47 + motion.phase;
      let texture = plantArt(p.kind, p.variant);
      texture = tinted(texture, this.palette.water, 0.18);

      ctx.save();
      ctx.globalAlpha = 0.64;
      ctx.translate(p.position.x, p.position.y);
      ctx.rotate(p.rotation);
      ctx.scale(p.scale, p.scale);
      if (this.reducedMotion) {
        drawTex(ctx, texture, bounds.x, bounds.y, bounds.w, bounds.h);
      } else {
        // 根部固定的分段弯动：网格行之间按高度平方偏移，近似 SKWarpGeometry。
        const bend = Math.sin(shared) * 0.036 + Math.sin(local * 0.83) * 0.018;
        for (let k = 0; k < 4; k++) {
          const yLo = rows[k], yHi = rows[k + 1];
          const mid = (yLo + yHi) / 2;
          const height = Math.max(0, (mid - 0.125) / 0.875);
          const flex = height * height;
          const flutter = Math.sin(local + height * 2.1) * 0.008 * flex;
          const xShift = (bend * flex + flutter) * bounds.w;
          const topY = bounds.y + yHi * bounds.h;
          const srcY = texture.height * (1 - yHi);
          const srcH = Math.max(1, texture.height * (yHi - yLo));
          ctx.save();
          ctx.translate(bounds.x + xShift, topY);
          ctx.scale(1, -1);
          ctx.drawImage(texture, 0, srcY, texture.width, srcH, 0, 0, bounds.w, (yHi - yLo) * bounds.h + 0.6);
          ctx.restore();
        }
      }
      ctx.restore();
    }
  }

  drawFish(ctx) {
    const s = this.settings;
    const daylight = this.daylight;
    const fishBlend = daylight.strength * 0.42;
    const order = this.swimmers.map((_, i) => i).sort((a, b) => (a % 3) - (b % 3) || a - b);
    for (const i of order) {
      const swimmer = this.swimmers[i];
      if (!this.designCache[i]) this.designCache[i] = initialDesign(i);
      const design = this.designCache[i];
      const parts = fishParts(design);
      const tint = fishBlend > 0 ? daylight.tint : 0;
      const body = fishBlend > 0 ? tinted(parts.body, tint, fishBlend) : parts.body;
      const tail = fishBlend > 0 ? tinted(parts.tail, tint, fishBlend) : parts.tail;
      const finUp = fishBlend > 0 ? tinted(parts.finUp, tint, fishBlend) : parts.finUp;
      const finDown = fishBlend > 0 ? tinted(parts.finDown, tint, fishBlend) : parts.finDown;
      const shadow = fishBlend > 0 ? tinted(parts.shadow, tint, fishBlend) : parts.shadow;
      const scale = swimmer.length / 115;
      const beat = this.simTime * (3.8 + s.swimSpeed * 1.4) + swimmer.phase;
      const tailRot = Math.sin(beat) * 0.3 - swimmer.turn * 0.15;

      ctx.save();
      ctx.translate(swimmer.x, swimmer.y);
      ctx.rotate(swimmer.angle);
      ctx.scale(scale, scale);
      ctx.save();
      ctx.translate(5, -8);
      drawTexC(ctx, shadow, 0, 0, FISH_PART_BOUNDS.body.w, FISH_PART_BOUNDS.body.h);
      ctx.restore();
      ctx.save();
      ctx.translate(-27, 0); ctx.rotate(tailRot);
      drawTexC(ctx, tail, 0, 0, FISH_PART_BOUNDS.tail.w, FISH_PART_BOUNDS.tail.h);
      ctx.restore();
      ctx.save();
      ctx.translate(12, 12); ctx.rotate(Math.sin(beat * 0.8) * 0.18);
      drawTexC(ctx, finUp, 0, 0, FISH_PART_BOUNDS.fin.w, FISH_PART_BOUNDS.fin.h);
      ctx.restore();
      ctx.save();
      ctx.translate(12, -12); ctx.rotate(-Math.sin(beat * 0.8 + 0.6) * 0.18);
      drawTexC(ctx, finDown, 0, 0, FISH_PART_BOUNDS.fin.w, FISH_PART_BOUNDS.fin.h);
      ctx.restore();
      ctx.save();
      ctx.scale(1, 1 + Math.sin(beat) * 0.012);
      drawTexC(ctx, body, 0, 0, FISH_PART_BOUNDS.body.w, FISH_PART_BOUNDS.body.h);
      ctx.restore();
      ctx.restore();
    }
  }

  drawGlints(ctx) {
    const d = this.settings.viewDistance;
    const w = 160 * d, h = 42 * d;
    for (const glint of this.glints) {
      ctx.save();
      ctx.globalAlpha = clamp(glint.alpha, 0, 1);
      ctx.translate(glint.x, glint.y);
      ctx.rotate(glint.rotation);
      drawTexC(ctx, glint.texture, 0, 0, w, h);
      ctx.restore();
    }
  }

  drawRipples(ctx) {
    const crest = crestArt();
    for (const ripple of this.ripples) {
      for (const ring of ripple.rings) {
        if (!ring.visible || ring.alpha <= 0.003) continue;
        ctx.save();
        ctx.globalAlpha = clamp(ring.alpha, 0, 1);
        drawTexC(ctx, crest, ripple.x, ripple.y, ring.r * 2, ring.r * 1.9);
        ctx.restore();
      }
    }
  }

  drawSurfacePlants(ctx) {
    const time = this.simTime, d = this.settings.viewDistance;
    const plantBlend = this.daylight.strength * 0.6;
    const tint = this.daylight.tint;
    const surface = this.placements.map((p, i) => ({ p, i })).filter(({ p }) => !p.submerged)
      .sort((a, b) => a.p.order - b.p.order || a.i - b.i);
    for (const { p, i } of surface) {
      const motion = this.motions[i];
      let x = p.position.x, y = p.position.y, rotation = p.rotation;
      if (!this.reducedMotion) {
        const shared = time * 0.34 + p.position.x / (720 * d) + p.position.y / (580 * d);
        const local = time * 0.47 + motion.phase;
        const drift = p.kind === 'duckweed' ? 9 : p.kind === 'flower' ? 3 : 5.5;
        const turn = p.kind === 'duckweed' ? 0.055 : p.kind === 'flower' ? 0.012 : 0.028;
        const dx = Math.sin(shared) * drift * 0.7 + Math.sin(local * 0.61) * drift * 0.3;
        const dy = Math.cos(shared * 0.81 + 0.5) * drift * 0.42 + Math.sin(local) * drift * 0.18;
        const push = this.rippleDisplacement(p.position.x, p.position.y, time);
        x += dx * d + push.x;
        y += dy * d + push.y;
        rotation += (Math.sin(shared * 0.76) * 0.65 + Math.sin(local * 0.87) * 0.35) * turn;
      }
      let texture = plantArt(p.kind, p.variant);
      if (plantBlend > 0) texture = tinted(texture, tint, plantBlend);
      const bounds = PLANT_BOUNDS[p.kind];
      ctx.save();
      ctx.translate(x, y);
      ctx.rotate(rotation);
      ctx.scale(p.scale, p.scale);
      drawTex(ctx, texture, bounds.x, bounds.y, bounds.w, bounds.h);
      ctx.restore();
    }
  }

  drawCrumbs(ctx) {
    ctx.lineWidth = 0.5;
    for (const crumb of this.crumbs) {
      const age = this.simTime - crumb.born;
      const alpha = age < crumb.life ? 1 : Math.max(0, 1 - (age - crumb.life) / 2);
      if (alpha <= 0) continue;
      ctx.globalAlpha = alpha;
      ctx.fillStyle = rgbCss(0xE7CAA0);
      ctx.strokeStyle = rgbCss(0x94724B);
      ctx.beginPath();
      ctx.ellipse(crumb.x, crumb.y, 2, 2, 0, 0, TAU);
      ctx.fill(); ctx.stroke();
    }
    ctx.globalAlpha = 1;
  }
}

// ── 宿主集成 ───────────────────────────────────────────────────────────────
(function boot() {
  const params = new URLSearchParams(location.search);
  // drive 模式：先装上 Wallpaper Engine 的 mousemove 协议桩，
  // 让 boot 走 WE 注册路径而不是 DOM 兜底，端到端验证集成契约。
  if (params.has('drive')) {
    window.wallpaperRegisterMousemoveListener = fn => { window.__weMove = fn; };
  }
  const settings = { ...DEFAULT_SETTINGS };
  if (params.has('theme')) settings.theme = params.get('theme');
  if (params.has('fish')) settings.fishCount = clamp(Number(params.get('fish')) || 24, 6, 60);
  if (params.has('speed')) settings.swimSpeed = clamp(Number(params.get('speed')) || 0.8, 0.3, 1.8);
  if (params.has('distance')) settings.viewDistance = clamp(Number(params.get('distance')) || 1.65, 1, 2.4);
  if (params.has('density')) settings.plantDensity = clamp(Number(params.get('density')) || 1.15, 0.5, 1.8);
  if (params.has('daylight')) settings.daylightMode = params.get('daylight');
  if (params.has('feed')) settings.feedMode = params.get('feed');
  if (params.has('mouse')) settings.mouseInteraction = params.get('mouse') !== 'off';
  if (params.has('clock')) setClockHour(clamp(Number(params.get('clock')) || 0, 0, 23));

  const canvas = document.getElementById('pond');
  const app = new PondApp(canvas, settings);
  const stream = new CursorStream();
  let configureTimer = 0;

  function applySettings() {
    app.configure();
  }
  function scheduleConfigure() {
    clearTimeout(configureTimer);
    configureTimer = setTimeout(applySettings, 160);
  }

  // Wallpaper Engine 用户属性（project.json general.properties）。
  window.wallpaperPropertyListener = {
    applyUserProperties(properties) {
      const map = {
        waterTheme: v => settings.theme = v,
        fishCount: v => settings.fishCount = clamp(v, 6, 60),
        swimSpeed: v => settings.swimSpeed = clamp(v, 0.3, 1.8),
        viewDistance: v => settings.viewDistance = clamp(v, 1, 2.4),
        plantDensity: v => settings.plantDensity = clamp(v, 0.5, 1.8),
        daylightMode: v => settings.daylightMode = v,
        mouseInteraction: v => settings.mouseInteraction = v,
        feedMode: v => settings.feedMode = v,
        lowPower: v => settings.lowPower = v,
      };
      for (const [name, apply] of Object.entries(map)) {
        if (properties[name] && properties[name].value !== undefined) apply(properties[name].value);
      }
      scheduleConfigure();
    },
  };

  function modifierHeld(event) {
    switch (settings.feedMode) {
      case 'ctrl': return event.ctrlKey;
      case 'shift': return event.shiftKey;
      case 'none': return true;
      default: return event.altKey;
    }
  }

  function onMouseMove(x, y, t) {
    if (!settings.mouseInteraction) return;
    const p = { x, y };
    const rippleAt = stream.moved(p, t);
    if (rippleAt) {
      const world = app.worldFromScreen(rippleAt.x, rippleAt.y);
      app.addRipple(world.x, world.y);
    }
    if (stream.startled(t)) {
      const world = app.worldFromScreen(x, y);
      app.startle(world);
    }
    app.cursor = { world: app.worldFromScreen(x, y), speed: stream.speed, time: app.simTime };
  }

  // WE：即使其他窗口在前，也全局转发光标位置。第三个参数仅供测试注入时间戳。
  if (typeof window.wallpaperRegisterMousemoveListener === 'function') {
    window.wallpaperRegisterMousemoveListener((x, y, t) => onMouseMove(x, y, t !== undefined ? t : performance.now() / 1000));
  }
  // DOM 兜底：普通浏览器与 Lively。
  document.addEventListener('mousemove', e => onMouseMove(e.clientX, e.clientY, performance.now() / 1000));
  document.addEventListener('mousedown', e => {
    if (!settings.mouseInteraction || !modifierHeld(e)) return;
    stream.pressed({ x: e.clientX, y: e.clientY }, performance.now() / 1000);
  });
  document.addEventListener('mousemove', e => {
    if (stream.tap) stream.dragged({ x: e.clientX, y: e.clientY });
  });
  document.addEventListener('mouseup', e => {
    if (!settings.mouseInteraction) return;
    const tap = stream.released(performance.now() / 1000);
    if (tap) {
      const world = app.worldFromScreen(tap.x, tap.y);
      app.feed(world);
    }
  });
  window.addEventListener('resize', () => app.resize());
  window.addEventListener('load', () => { if (app.cssW < 2 || app.cssH < 2) app.resize(); });

  // “自动”时段每分钟对表一次。
  setInterval(() => {
    if (settings.daylightMode !== 'auto') return;
    if (effectiveDaylight('auto').key !== app.daylight.key) app.configure();
  }, 60000);

  app.resize();

  // ── 自检（对应 macOS 版 --self-test 的核心断言），?selftest=1 触发，结果写入标题。
  if (params.has('selftest')) {
    const failures = [];
    const check = (condition, message) => { if (!condition) failures.push(message); };
    // 60 尾 × 3 档速度 × 3 种尺寸 × 60 秒：有限值、边界、转向上限。
    for (const speed of [0.3, 0.8, 1.8]) {
      for (const [width, height] of [[1440, 900], [800, 600], [3440, 1440]]) {
        const random = new SeededRandom();
        const school = [];
        for (let i = 0; i < 60; i++) {
          school.push(new Swimmer(random.range(28, width - 28), random.range(28, height - 28),
            random.range(0, TAU), random.range(24, 48), random.range(0, TAU), 100));
        }
        for (let frame = 0; frame < 1800; frame++) {
          const target = frame > 900 ? [{ x: width / 2, y: height / 2 }] : [];
          const points = school.map(f => ({ x: f.x, y: f.y }));
          for (let i = 0; i < school.length; i++) {
            school[i].step(1 / 30, frame / 30, width, height, speed, target, points, i, null, false, 0);
            const fish = school[i];
            if (!Number.isFinite(fish.x) || !Number.isFinite(fish.y) || !Number.isFinite(fish.angle)) { failures.push('鱼群状态必须为有限数'); break; }
            if (fish.x < 28 || fish.x > width - 28 || fish.y < 28 || fish.y > height - 28) { failures.push('金鱼不能越过边界'); break; }
            if (Math.abs(fish.turn) > 2.2 + 1e-9) { failures.push('转向不能超过受惊档上限'); break; }
          }
          if (failures.length) break;
        }
        if (failures.length) break;
      }
      if (failures.length) break;
    }
    // 投喂：落点准确、多处并存、上限 5 处。
    app.feed({ x: 500, y: 400 });
    check(app.foodSpots.length === 1 && app.foodSpots[0].x === 500 && app.foodSpots[0].y === 400, '投喂必须落在指定位置');
    app.feed({ x: 700, y: 400 });
    check(app.foodSpots.length === 2, '多处投喂必须并存');
    for (let i = 0; i < 6; i++) app.feed({ x: 100 + i * 10, y: 100 });
    check(app.foodSpots.length === 5, '投喂上限 5 处');
    // 涟漪节流与急挥惊吓只触发一次（对照 Checks.swift runInteractionChecks）。
    const stream2 = new CursorStream();
    let ripples = 0;
    for (let k = 0; k < 20; k++) {
      if (stream2.moved({ x: k * 5, y: 3 }, k * 0.05)) ripples++;
    }
    check(ripples >= 2 && ripples <= 6, '缓动光标应按间距泛起涟漪，而不是每帧刷屏');
    check(!stream2.startled(1.1), '缓动不应惊吓鱼群');
    stream2.moved({ x: 700, y: 3 }, 1.13);
    check(stream2.startled(1.13), '急挥必须惊散鱼群');
    check(!stream2.startled(1.14), '同一次急挥只惊吓一次');
    const stream3 = new CursorStream();
    stream3.pressed({ x: 10, y: 10 }, 1.0);
    stream3.dragged({ x: 40, y: 10 });
    check(stream3.released(1.1) === null, '拖拽取消轻点');
    const stream4 = new CursorStream();
    stream4.pressed({ x: 10, y: 10 }, 1.0);
    check(stream4.released(1.2) !== null, '0.2 秒内松开算轻点');
    // 时段：全天映射、夜晚更暗更冷、傍晚偏暖。
    const hours = { 5: 'dawn', 12: 'noon', 18: 'dusk', 23: 'night' };
    for (const [hour, key] of Object.entries(hours)) {
      check(effectiveDaylight('auto', new Date(2026, 9, 4, hour, 0)).key === key, `小时 ${hour} 应为 ${key}`);
    }
    const noonLum = lum(DAYLIGHTS.noon.tint), nightLum = lum(DAYLIGHTS.night.tint);
    check(nightLum < noonLum, '夜晚时段色应更暗');
    // 世界坐标换算往返。
    const world = app.worldFromScreen(app.cssW / 2, app.cssH / 2);
    check(Math.abs(world.x - app.worldW / 2) < 1e-6 && Math.abs(world.y - app.worldH / 2) < 1e-6, '屏幕中心应映射到世界中心');
    document.title = failures.length ? `SELFTEST-FAIL: ${failures[0]}` : 'SELFTEST-PASS';
    const summary = document.createElement('pre');
    summary.textContent = document.title;
    document.body.insertBefore(summary, document.body.firstChild);
    return;
  }

  // ── drive：模拟 Wallpaper Engine 协议的端到端交互场景，结果写入标题。
  if (params.has('drive')) {
    const failures = [];
    const check = (condition, message) => { if (!condition) failures.push(message); };
    const screenFromWorld = (wx, wy) => ({
      x: (wx - app.worldW / 2) / settings.viewDistance + app.cssW / 2,
      y: app.cssH / 2 - (wy - app.worldH / 2) / settings.viewDistance,
    });
    setTimeout(() => {
      // 1. WE 集成契约：壁纸确实通过 wallpaperRegisterMousemoveListener 注册了监听。
      check(typeof window.__weMove === 'function', 'WE mousemove 监听应已注册');
      // 2. 缓动扫过：固定 100 px/s 横移 150px，应泛起多条涟漪且不惊吓。
      const t0 = performance.now() / 1000;
      const before = app.swimmers.map(f => f.startledUntil);
      for (let k = 0; k <= 45; k++) {
        window.__weMove(60 + k * 150 / 45, app.cssH / 3, t0 + k / 30);
      }
      check(app.ripples.length >= 3 && app.ripples.length <= 20, '缓动应按节流泛起涟漪');
      check(app.swimmers.every((f, i) => f.startledUntil === before[i]), '缓动不应惊散鱼群');
      // 3. 急挥：朝最近的鱼快速甩动光标，应惊散它。
      // MouseEvent 派发时 Chrome 会把小数坐标取整，点击一律用整数坐标。
      const clickX = Math.floor(app.cssW / 2), clickY = Math.floor(app.cssH / 2);
      const center = app.worldFromScreen(clickX, clickY);
      let near = 0;
      for (let i = 1; i < app.swimmers.length; i++) {
        if (Math.hypot(app.swimmers[i].x - center.x, app.swimmers[i].y - center.y) <
            Math.hypot(app.swimmers[near].x - center.x, app.swimmers[near].y - center.y)) near = i;
      }
      const flick = screenFromWorld(app.swimmers[near].x, app.swimmers[near].y);
      const t1 = performance.now() / 1000;
      window.__weMove(flick.x - 300, flick.y, t1);
      window.__weMove(flick.x, flick.y, t1 + 0.02);
      check(app.swimmers[near].startledUntil > app.simTime, '急挥应惊散附近的鱼');
      // 4. 修饰键轻点投喂，饲料落在光标的世界坐标处。
      const spotBefore = app.foodSpots.length;
      document.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, clientX: clickX, clientY: clickY, altKey: true }));
      document.dispatchEvent(new MouseEvent('mouseup', { bubbles: true, clientX: clickX, clientY: clickY, altKey: true }));
      check(app.foodSpots.length === spotBefore + 1, '修饰键轻点应投喂');
      const spot = app.foodSpots[app.foodSpots.length - 1];
      check(spot && Math.abs(spot.x - center.x) < 0.01 && Math.abs(spot.y - center.y) < 0.01, `饲料应落在光标处 got=${spot && spot.x.toFixed(2)},${spot && spot.y.toFixed(2)} want=${center.x.toFixed(2)},${center.y.toFixed(2)} screen=${app.cssW}x${app.cssH}`);
      // 5. 普通点击不投喂。
      document.dispatchEvent(new MouseEvent('mousedown', { bubbles: true, clientX: 100, clientY: 100 }));
      document.dispatchEvent(new MouseEvent('mouseup', { bubbles: true, clientX: 100, clientY: 100 }));
      check(app.foodSpots.length === spotBefore + 1, '普通点击不应投喂');
      // 6. WE 用户属性管道：换主题、改数量、拉视野，去抖后应全部生效并清掉旧波纹。
      window.wallpaperPropertyListener.applyUserProperties({
        waterTheme: { value: 'ink' }, fishCount: { value: 12 }, viewDistance: { value: 1.2 },
      });
      setTimeout(() => {
        check(settings.theme === 'ink' && app.swimmers.length === 12 && Math.abs(settings.viewDistance - 1.2) < 1e-9, 'WE 用户属性应生效');
        check(app.ripples.length === 0, '视野变化应清理旧坐标里的波纹');
        document.title = failures.length ? `DRIVE-FAIL: ${failures[0]}` : 'DRIVE-PASS';
        const summary = document.createElement('pre');
        summary.textContent = document.title;
        document.body.insertBefore(summary, document.body.firstChild);
      }, 400);
    }, 200);
  }

  // ── soak：同步快进 N 秒模拟（不渲染），检查有限值与数组上限。
  if (params.has('soak')) {
    const failures = [];
    const check = (condition, message) => { if (!condition) failures.push(message); };
    const seconds = Math.min(86400, Number(params.get('soak')) || 600);
    for (let i = 0; i < seconds * 30; i++) app.update(1 / 30);
    check(app.swimmers.every(f => Number.isFinite(f.x) && Number.isFinite(f.y) && Number.isFinite(f.angle)), '长时间模拟后鱼群状态仍应为有限数');
    check(app.ripples.length <= 20, '涟漪对象数量应有上限');
    check(app.crumbs.length <= 16 * 5, '饲料碎屑数量应有上限');
    check(app.foodSpots.length <= 5, '投喂点数量应有上限');
    check(app.glints.length >= 4 && app.glints.length <= 12, '反光数量应稳定');
    document.title = failures.length ? `SOAK-FAIL: ${failures[0]}` : `SOAK-PASS (${seconds}s)`;
    const summary = document.createElement('pre');
    summary.textContent = document.title;
    document.body.insertBefore(summary, document.body.firstChild);
  }

  // 预走 t 秒模拟（截图/首帧更自然，不跳渲染）。
  const presettle = Number(params.get('t')) || 0;
  for (let i = 0; i < presettle * 30; i++) app.update(1 / 30);

  let last = performance.now(), accumulator = 0;
  let statsHud = null, renderMs = 0, updateMs = 0;
  if (params.has('stats')) {
    statsHud = document.createElement('div');
    statsHud.style.cssText = 'position:fixed;top:10px;left:10px;z-index:9;font:11px/1.5 Menlo,monospace;' +
      'color:#EDEAD8;background:rgba(16,30,26,.72);padding:6px 10px;border-radius:6px;pointer-events:none;white-space:pre';
    document.body.appendChild(statsHud);
  }
  function frame(now) {
    if (!params.has('freeze')) requestAnimationFrame(frame);
    if (document.hidden) { last = now; return; }
    const step = 1 / (settings.lowPower ? 20 : 30);
    accumulator += Math.min(0.1, (now - last) / 1000);
    last = now;
    let steps = 0;
    const updateStart = performance.now();
    while (accumulator >= step && steps < 3) {
      app.update(step);
      accumulator -= step;
      steps++;
    }
    if (steps === 3) accumulator = 0;
    updateMs = updateMs * 0.9 + (performance.now() - updateStart) * 0.1;
    const renderStart = performance.now();
    app.render();
    renderMs = renderMs * 0.9 + (performance.now() - renderStart) * 0.1;
    if (statsHud) {
      statsHud.__n = (statsHud.__n || 0) + 1;
      if (!statsHud.__at) statsHud.__at = now;
      else if (now - statsHud.__at >= 500) {
        const fpsNow = Math.round(statsHud.__n * 1000 / (now - statsHud.__at));
        statsHud.__n = 0; statsHud.__at = now;
        statsHud.textContent = `${fpsNow} fps · update ${updateMs.toFixed(1)}ms · render ${renderMs.toFixed(1)}ms\n` +
          `fish ${app.swimmers.length} · ripples ${app.ripples.length} · crumbs ${app.crumbs.length} · t ${app.simTime.toFixed(0)}s`;
      }
    }
  }
  requestAnimationFrame(frame);
})();
