import AppKit
import SpriteKit

// 池塘小居民：小乌龟、蝌蚪与田螺。与金鱼同一套画法——纯色形状、细线与颗粒，
// 独立高清纹理按外观缓存，时段光色用 colorBlendFactor 染在实例上。

enum TurtlePainter {
    static var cache: [Int: [FishArtPart]] = [:]
    static let shellBounds = CGRect(x: -58, y: -34, width: 106, height: 68)
    static let headBounds = CGRect(x: -8, y: -14, width: 36, height: 28)
    static func flipperBounds(side: Double) -> CGRect {
        side > 0 ? CGRect(x: -36, y: -6, width: 46, height: 42) : CGRect(x: -36, y: -36, width: 46, height: 42)
    }
    static func parts(_ variant: Int) -> [FishArtPart] {
        if let cached = cache[variant] { return cached }
        let bases: [UInt32] = [0x5C6E45, 0x566A4A, 0x64714A, 0x4E6242]
        let specs: [(CGRect, (CGContext) -> Void)] = [
            (shellBounds, { drawShell($0, variant: variant, base: bases[variant % bases.count]) }),
            (headBounds, { drawHead($0, variant: variant) }),
            (flipperBounds(side: 1), { drawFlipper($0, side: 1) }),
            (flipperBounds(side: -1), { drawFlipper($0, side: -1) }),
            (shellBounds, { ctx in
                ctx.saveGState(); ctx.translateBy(x: 3, y: -6)
                fill(ctx, shellOutline(), 0x08251D, alpha: 0.25); ctx.restoreGState()
            })
        ]
        let result = specs.map { bounds, drawing in FishArtPart(texture: SKTexture(cgImage: bitmap(bounds: bounds, scale: 4, draw: drawing)), bounds: bounds) }
        if cache.count > 16 { cache.removeAll() }
        cache[variant] = result
        return result
    }
    static func shellOutline() -> CGPath {
        path { p in
            p.move(to: CGPoint(x: 44, y: 0))
            p.addCurve(to: CGPoint(x: 10, y: 30), control1: CGPoint(x: 44, y: 20), control2: CGPoint(x: 30, y: 30))
            p.addCurve(to: CGPoint(x: -34, y: 22), control1: CGPoint(x: -8, y: 30), control2: CGPoint(x: -24, y: 28))
            p.addCurve(to: CGPoint(x: -46, y: 0), control1: CGPoint(x: -42, y: 16), control2: CGPoint(x: -46, y: 8))
            p.addCurve(to: CGPoint(x: -34, y: -22), control1: CGPoint(x: -46, y: -8), control2: CGPoint(x: -42, y: -16))
            p.addCurve(to: CGPoint(x: 10, y: -30), control1: CGPoint(x: -24, y: -28), control2: CGPoint(x: -8, y: -30))
            p.addCurve(to: CGPoint(x: 44, y: 0), control1: CGPoint(x: 30, y: -30), control2: CGPoint(x: 44, y: -20))
            p.closeSubpath()
        }
    }
    // 盾片：中央一列 5 片，两侧各 4 片，圆角菱形cell，暗线勾缝。
    static func scute(_ ctx: CGContext, _ x: Double, _ y: Double, _ w: Double, _ h: Double, _ hex: UInt32) {
        let cell = path { p in
            p.move(to: CGPoint(x: x - w, y: y))
            p.addQuadCurve(to: CGPoint(x: x, y: y + h), control: CGPoint(x: x - w * 0.55, y: y + h * 0.75))
            p.addQuadCurve(to: CGPoint(x: x + w, y: y), control: CGPoint(x: x + w * 0.55, y: y + h * 0.75))
            p.addQuadCurve(to: CGPoint(x: x, y: y - h), control: CGPoint(x: x + w * 0.55, y: y - h * 0.75))
            p.addQuadCurve(to: CGPoint(x: x - w, y: y), control: CGPoint(x: x - w * 0.55, y: y - h * 0.75))
        }
        fill(ctx, cell, hex, alpha: 0.55)
        line(ctx, cell, 0x2F3B28, width: 0.8, alpha: 0.5)
    }
    static func drawShell(_ ctx: CGContext, variant: Int, base: UInt32) {
        let outline = shellOutline()
        // 短尾巴藏在壳后缘。
        let tail = path { p in
            p.move(to: CGPoint(x: -44, y: 6))
            p.addQuadCurve(to: CGPoint(x: -56, y: 0), control: CGPoint(x: -52, y: 5))
            p.addQuadCurve(to: CGPoint(x: -44, y: -6), control: CGPoint(x: -52, y: -5))
            p.closeSubpath()
        }
        fill(ctx, tail, base); line(ctx, tail, 0x39472F, width: 0.6, alpha: 0.6)
        fill(ctx, outline, base)
        ctx.saveGState(); ctx.addPath(outline); ctx.clip()
        var random = SeededRandom(state: UInt64(52401 + variant * 7717))
        for _ in 0..<70 {
            let at = CGPoint(x: random.range(-44, 42), y: random.range(-28, 28))
            let patch = PondEnvironment.organic(center: at, radius: random.range(3, 12), random: &random, count: 8)
            fill(ctx, patch, random.next() < 0.5 ? 0x39472F : 0x93995F, alpha: random.range(0.03, 0.08))
        }
        let lights: [UInt32] = [0x6E7C50, 0x687855, 0x768254, 0x5F7450]
        for i in 0..<5 { scute(ctx, 28 - Double(i) * 16, 0, 7.6, 9.5, lights[(i + variant) % lights.count]) }
        for i in 0..<4 {
            for side in [-1.0, 1.0] { scute(ctx, 20 - Double(i) * 16, side * 19, 7, 8.2, lights[(i + 1 + variant) % lights.count]) }
        }
        line(ctx, path { p in p.move(to: CGPoint(x: 40, y: 0)); p.addLine(to: CGPoint(x: -45, y: 0)) }, 0x2F3B28, width: 0.7, alpha: 0.3)
        for _ in 0..<90 {
            let r = random.range(0.08, 0.3)
            ctx.setFillColor(color(0xC9CD9A, random.range(0.04, 0.13)).cgColor)
            ctx.fillEllipse(in: CGRect(x: random.range(-44, 42), y: random.range(-28, 28), width: r, height: r))
        }
        ctx.restoreGState()
        line(ctx, outline, 0x8B9763, width: 1.1, alpha: 0.45)
        line(ctx, outline, 0x2F3B28, width: 1.0, alpha: 0.7)
    }
    static func drawHead(_ ctx: CGContext, variant: Int) {
        let head = path { p in
            p.move(to: CGPoint(x: -7, y: 11))
            p.addCurve(to: CGPoint(x: 16, y: 7), control1: CGPoint(x: 2, y: 12), control2: CGPoint(x: 11, y: 10))
            p.addCurve(to: CGPoint(x: 26, y: 0), control1: CGPoint(x: 21, y: 4), control2: CGPoint(x: 26, y: 2))
            p.addCurve(to: CGPoint(x: 16, y: -7), control1: CGPoint(x: 26, y: -2), control2: CGPoint(x: 21, y: -4))
            p.addCurve(to: CGPoint(x: -7, y: -11), control1: CGPoint(x: 11, y: -10), control2: CGPoint(x: 2, y: -12))
            p.addCurve(to: CGPoint(x: -7, y: 11), control1: CGPoint(x: -11, y: -6), control2: CGPoint(x: -11, y: 6))
        }
        fill(ctx, head, 0x707F50)
        ctx.saveGState(); ctx.addPath(head); ctx.clip()
        fill(ctx, ellipsePath(CGRect(x: 2, y: -7, width: 18, height: 14)), 0x8B9763, alpha: 0.38)
        for x in [-4.0, 0.5, 5.0] {
            line(ctx, path { p in p.move(to: CGPoint(x: x, y: -9)); p.addQuadCurve(to: CGPoint(x: x + 1.6, y: 9), control: CGPoint(x: x - 2.2, y: 0)) }, 0x4E5A38, width: 0.8, alpha: 0.45)
        }
        var random = SeededRandom(state: UInt64(3121 + variant * 977))
        for _ in 0..<40 {
            let r = random.range(0.1, 0.35)
            ctx.setFillColor(color(0xA8B476, random.range(0.05, 0.14)).cgColor)
            ctx.fillEllipse(in: CGRect(x: random.range(-7, 24), y: random.range(-11, 11), width: r, height: r))
        }
        ctx.restoreGState()
        line(ctx, head, 0x46543A, width: 0.6, alpha: 0.7)
        for y in [-6.0, 6.0] {
            ctx.setFillColor(color(0x1F2A1A).cgColor); ctx.fillEllipse(in: CGRect(x: 10, y: y - 1.3, width: 2.7, height: 2.6))
            ctx.setFillColor(color(0xE9EDD4).cgColor); ctx.fillEllipse(in: CGRect(x: 11, y: y - 0.6, width: 0.9, height: 0.9))
        }
        for y in [-1.6, 0.4] {
            ctx.setFillColor(color(0x2A3524).cgColor); ctx.fillEllipse(in: CGRect(x: 24, y: y, width: 0.8, height: 0.8))
        }
    }
    static func drawFlipper(_ ctx: CGContext, side: Double) {
        let flipper = path { p in
            p.move(to: CGPoint(x: 8, y: 0))
            p.addCurve(to: CGPoint(x: -26, y: side * 24), control1: CGPoint(x: -2, y: side * 16), control2: CGPoint(x: -14, y: side * 25))
            p.addCurve(to: CGPoint(x: -33, y: side * 15), control1: CGPoint(x: -30, y: side * 26), control2: CGPoint(x: -34, y: side * 21))
            p.addCurve(to: CGPoint(x: -2, y: side * -5), control1: CGPoint(x: -22, y: side * 6), control2: CGPoint(x: -10, y: side * 1))
            p.closeSubpath()
        }
        fill(ctx, flipper, 0x5A6A44, alpha: 0.94)
        line(ctx, flipper, 0x39472F, width: 0.6, alpha: 0.55)
        for i in 1...3 {
            line(ctx, path { p in
                p.move(to: CGPoint(x: 2, y: side))
                p.addQuadCurve(to: CGPoint(x: -10 - Double(i) * 6.5, y: side * (7 + Double(i) * 5)), control: CGPoint(x: -6 - Double(i) * 4, y: side * (4 + Double(i) * 2.6)))
            }, 0x39472F, width: 0.5, alpha: 0.32)
        }
        for x in [-27.0, -30.5] {
            ctx.setFillColor(color(0x22301F).cgColor); ctx.fillEllipse(in: CGRect(x: x, y: side * 21 - 0.8, width: 2.4, height: 1.6))
        }
    }
}

func ellipsePath(_ rect: CGRect) -> CGPath { CGPath(ellipseIn: rect, transform: nil) }

enum TadpolePainter {
    static var cache: [Int: FishArtPart] = [:]
    static let bounds = CGRect(x: -31, y: -11, width: 49, height: 22)
    static func part(_ variant: Int) -> FishArtPart {
        if let cached = cache[variant] { return cached }
        let texture = SKTexture(cgImage: bitmap(bounds: bounds, scale: 4) { draw($0, variant: variant) })
        let result = FishArtPart(texture: texture, bounds: bounds)
        cache[variant] = result
        return result
    }
    static func draw(_ ctx: CGContext, variant: Int) {
        // 尾巴：一条弯过的粗线当半透明尾鳍，中间细线是尾索。
        let spine = path { p in
            p.move(to: CGPoint(x: -1, y: 0))
            for i in 1...12 {
                let t = Double(i) / 12
                p.addLine(to: CGPoint(x: -1 - t * 27, y: sin(t * 5.2 + Double(variant) * 1.1) * 3.4 * (1 - t * 0.3)))
            }
        }
        line(ctx, spine, 0x3A4A37, width: 3.6, alpha: 0.42)
        line(ctx, spine, 0x2B382A, width: 1.1, alpha: 0.8)
        let body = ellipsePath(CGRect(x: -1, y: -6, width: 17, height: 12))
        fill(ctx, body, 0x2E3B2C)
        ctx.saveGState(); ctx.addPath(body); ctx.clip()
        fill(ctx, ellipsePath(CGRect(x: 2, y: -4.5, width: 9, height: 7)), 0x55654B, alpha: 0.5)
        var random = SeededRandom(state: UInt64(8123 + variant * 613))
        for _ in 0..<24 {
            let r = random.range(0.1, 0.4)
            ctx.setFillColor(color(0x141F13, random.range(0.1, 0.3)).cgColor)
            ctx.fillEllipse(in: CGRect(x: random.range(-1, 16), y: random.range(-6, 6), width: r, height: r))
        }
        ctx.restoreGState()
        line(ctx, body, 0x1C261B, width: 0.5, alpha: 0.7)
        for y in [-2.6, 2.6] {
            ctx.setFillColor(color(0x0F170E).cgColor); ctx.fillEllipse(in: CGRect(x: 12, y: y - 1.1, width: 2.2, height: 2.2))
        }
    }
}

enum SnailPainter {
    static var cache: [Int: FishArtPart] = [:]
    static let bounds = CGRect(x: -20, y: -17, width: 46, height: 34)
    static func part(_ variant: Int) -> FishArtPart {
        if let cached = cache[variant] { return cached }
        let texture = SKTexture(cgImage: bitmap(bounds: bounds, scale: 4) { draw($0, variant: variant) })
        let result = FishArtPart(texture: texture, bounds: bounds)
        cache[variant] = result
        return result
    }
    static func draw(_ ctx: CGContext, variant: Int) {
        // 腹足与前触角（眼睛长在触角尖上）。
        let foot = path { p in
            p.move(to: CGPoint(x: 17, y: 5.5))
            p.addCurve(to: CGPoint(x: -12, y: 6.5), control1: CGPoint(x: 13, y: 7.5), control2: CGPoint(x: -4, y: 8))
            p.addQuadCurve(to: CGPoint(x: -14, y: 0), control: CGPoint(x: -15.5, y: 3.5))
            p.addQuadCurve(to: CGPoint(x: -12, y: -6.5), control: CGPoint(x: -15.5, y: -3.5))
            p.addCurve(to: CGPoint(x: 17, y: -5.5), control1: CGPoint(x: -4, y: -8), control2: CGPoint(x: 13, y: -7.5))
            p.addQuadCurve(to: CGPoint(x: 17, y: 5.5), control: CGPoint(x: 20.5, y: 0))
        }
        fill(ctx, foot, 0x7E8B58)
        ctx.saveGState(); ctx.addPath(foot); ctx.clip()
        fill(ctx, ellipsePath(CGRect(x: -14, y: -3, width: 32, height: 6)), 0x99A56C, alpha: 0.45)
        ctx.restoreGState()
        line(ctx, foot, 0x4E5A38, width: 0.5, alpha: 0.6)
        for side in [-1.0, 1.0] {
            let feeler = path { p in
                p.move(to: CGPoint(x: 14, y: side * 3.5))
                p.addQuadCurve(to: CGPoint(x: 24.5, y: side * 8), control: CGPoint(x: 19, y: side * 5.5))
            }
            line(ctx, feeler, 0x6B7A4C, width: 1.1)
            ctx.setFillColor(color(0x222B1C).cgColor); ctx.fillEllipse(in: CGRect(x: 23.6, y: side * 8 - 1.3, width: 2.6, height: 2.6))
            ctx.setFillColor(color(0xE9EDD4).cgColor); ctx.fillEllipse(in: CGRect(x: 24.4, y: side * 8 - 0.4, width: 0.9, height: 0.9))
        }
        // 壳：底色圆 + 双圈螺旋细线 + 上缘高光，全部纯色描边。
        ctx.setFillColor(color(0x16372A, 0.25).cgColor)
        ctx.fillEllipse(in: CGRect(x: -14, y: -13, width: 25, height: 24))
        let shell = ellipsePath(CGRect(x: -14, y: -12, width: 24, height: 24))
        fill(ctx, shell, variant % 2 == 0 ? 0x9A7B54 : 0x8A6F52)
        var random = SeededRandom(state: UInt64(4477 + variant * 331))
        ctx.saveGState(); ctx.addPath(shell); ctx.clip()
        for _ in 0..<26 {
            let at = CGPoint(x: random.range(-13, 9), y: random.range(-11, 11))
            let patch = PondEnvironment.organic(center: at, radius: random.range(1.5, 4.5), random: &random, count: 7)
            fill(ctx, patch, random.next() < 0.5 ? 0x6E523A : 0xB08D60, alpha: random.range(0.05, 0.12))
        }
        ctx.restoreGState()
        let spiralStrokes: [(UInt32, CGFloat, CGFloat)] = [(0x6E523A, 2.0, 0.85), (0xB08D60, 0.8, 0.55)]
        for (hex, width, alpha) in spiralStrokes {
            let spiral = path { p in
                for i in 0...48 {
                    let t = Double(i) / 48
                    let angle = t * tau * 2.35 + Double(variant) * 0.7
                    let r = 11 - t * 9.4
                    let point = CGPoint(x: -2 + cos(angle) * r, y: sin(angle) * r)
                    if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
                }
            }
            line(ctx, spiral, hex, width: width, alpha: alpha)
        }
        line(ctx, shell, 0x4E3A28, width: 1.0, alpha: 0.75)
        line(ctx, path { p in p.addArc(center: CGPoint(x: -2, y: 0), radius: 8.8, startAngle: 1.9, endAngle: 2.9, clockwise: false) }, 0xD9C49A, width: 1.4, alpha: 0.6)
    }
}

// 乌龟慢条斯理：平缓巡游、绕开边界、认食但不冲刺；每隔一段时间上浮换气，
// 换气中途泛起一圈涟漪。返回 true 表示这一帧正在换气触水。
struct TurtleBrain {
    var x: Double, y: Double, angle: Double, cruise: Double, phase: Double
    var turn: Double = 0
    private(set) var breathing = false
    var nextBreath: Double, breathMoment = 0.0, breathed = true
    init(x: Double, y: Double, angle: Double, cruise: Double, phase: Double) {
        self.x = x; self.y = y; self.angle = angle; self.cruise = cruise; self.phase = phase
        nextBreath = 6 + phase  // 首次换气散布在 6–12 秒
    }
    mutating func step(dt: Double, time: Double, width: Double, height: Double, speed: Double, targets: [CGPoint]) -> Bool {
        var rippleNow = false
        if !breathing && time >= nextBreath {
            breathing = true; breathed = false; breathMoment = time + 1.0
        }
        if breathing && !breathed && time >= breathMoment {
            breathed = true; rippleNow = true
        }
        if breathing && time >= breathMoment + 1.6 {
            breathing = false
            nextBreath = time + 18 + sin(phase * 3.1) * 8  // 10–26 秒后再换气
        }
        var desired = angle + sin(time * 0.09 + phase) * 0.7 + sin(time * 0.033 + phase * 2.3) * 0.35
        var fx = cos(desired), fy = sin(desired)
        let margin = min(110.0, min(width, height) * 0.16)
        if x < margin { fx += (margin - x) / margin * 2.5 }
        if x > width - margin { fx -= (x - width + margin) / margin * 2.5 }
        if y < margin { fy += (margin - y) / margin * 2.5 }
        if y > height - margin { fy -= (y - height + margin) / margin * 2.5 }
        if let nearest = targets.min(by: { hypot($0.x - x, $0.y - y) < hypot($1.x - x, $1.y - y) }) {
            let distance = hypot(nearest.x - x, nearest.y - y)
            if distance > 26 {
                fx += (nearest.x - x) / distance * 1.5
                fy += (nearest.y - y) / distance * 1.5
            }
        }
        desired = atan2(fy, fx)
        let delta = atan2(sin(desired - angle), cos(desired - angle))
        turn += (clamp(delta * 1.1, -0.55, 0.55) - turn) * min(1, dt * 1.4)
        angle += turn * dt
        var velocity = cruise * speed * (1 + 0.08 * sin(time * 0.5 + phase))
        if breathing { velocity *= 0.22 }
        x = clamp(x + cos(angle) * velocity * dt, 30, max(30, width - 30))
        y = clamp(y + sin(angle) * velocity * dt, 30, max(30, height - 30))
        return rippleNow
    }
}

// 蝌蚪成群：淡淡抱团、彼此留距，时不时猛窜一下；被惊吓时四散弹开。
struct TadpoleBrain {
    var x: Double, y: Double, angle: Double, cruise: Double, phase: Double
    var turn: Double = 0
    var dartUntil = 0.0, nextDart = 0.0
    var startledUntil = 0.0, startledFrom = CGPoint.zero
    mutating func step(dt: Double, time: Double, width: Double, height: Double, speed: Double, center: CGPoint, neighbors: [CGPoint]) {
        var fx = cos(angle) * 0.6, fy = sin(angle) * 0.6
        fx += (center.x - x) * 0.004
        fy += (center.y - y) * 0.004
        for p in neighbors {
            let dx = x - p.x, dy = y - p.y, d2 = dx * dx + dy * dy
            if d2 > 1 && d2 < 26 * 26 {
                let d = sqrt(d2)
                fx += dx / d * (1 - d / 26) * 1.3
                fy += dy / d * (1 - d / 26) * 1.3
            }
        }
        let margin = 70.0
        if x < margin { fx += (margin - x) / margin * 2.5 }
        if x > width - margin { fx -= (x - width + margin) / margin * 2.5 }
        if y < margin { fy += (margin - y) / margin * 2.5 }
        if y > height - margin { fy -= (y - height + margin) / margin * 2.5 }
        let panicking = startledUntil > time
        if panicking {
            let dx = x - startledFrom.x, dy = y - startledFrom.y, d = max(1, hypot(dx, dy))
            fx += dx / d * 3.0; fy += dy / d * 3.0
        }
        let desired = atan2(fy, fx)
        let delta = atan2(sin(desired - angle), cos(desired - angle))
        turn += (clamp(delta * (panicking ? 5 : 3), -3, 3) - turn) * min(1, dt * 6)
        angle += turn * dt
        let darty = dartUntil > time ? 2.1 : 1
        let loaf = panicking || dartUntil > time ? 1 : 0.4 + 0.25 * sin(time * 0.9 + phase)
        let velocity = cruise * speed * loaf * darty
        x = clamp(x + cos(angle) * velocity * dt, 16, max(16, width - 16))
        y = clamp(y + sin(angle) * velocity * dt, 16, max(16, height - 16))
    }
}

// 田螺贴着池底慢慢爬，爬一阵歇一阵，靠边时缓慢折返。
struct SnailBrain {
    var x: Double, y: Double, angle: Double, phase: Double
    var restUntil = 0.0, nextRest = 0.0
    mutating func step(dt: Double, time: Double, width: Double, height: Double, speed: Double, rng: inout SeededRandom) -> Bool {
        if time >= nextRest {
            restUntil = time + rng.range(6, 15)
            nextRest = restUntil + rng.range(9, 22)
        }
        guard time < restUntil else { return false }
        angle += sin(time * 0.16 + phase * 2.7) * 0.22 * dt
        let margin = 70.0
        if x < margin || x > width - margin || y < margin || y > height - margin {
            let home = atan2(height / 2 - y, width / 2 - x)
            angle += clamp(atan2(sin(home - angle), cos(home - angle)), -1, 1) * dt * 0.9
        }
        x = clamp(x + cos(angle) * 6.5 * speed * dt, 24, max(24, width - 24))
        y = clamp(y + sin(angle) * 6.5 * speed * dt, 24, max(24, height - 24))
        return true
    }
}

final class TurtleNode: SKNode {
    let shell = SKNode(), head = SKNode(), shadowLayer = SKNode()
    let frontLeft = SKNode(), frontRight = SKNode(), backLeft = SKNode(), backRight = SKNode()
    private var tintables: [SKSpriteNode] = []
    private(set) var daylightBlend: CGFloat = 0
    let phase: Double
    init(variant: Int, size: Double) {
        phase = Double(variant) * 1.7 + 0.6
        super.init()
        let parts = TurtlePainter.parts(variant % 4)
        frontLeft.position = CGPoint(x: 22, y: 20); frontRight.position = CGPoint(x: 22, y: -20)
        backLeft.position = CGPoint(x: -30, y: 16); backRight.position = CGPoint(x: -30, y: -16)
        backLeft.setScale(0.72); backRight.setScale(0.72)
        shadowLayer.position = CGPoint(x: 4, y: -7); shadowLayer.zPosition = -3
        backLeft.zPosition = -2; backRight.zPosition = -2
        head.zPosition = -1; frontLeft.zPosition = -1; frontRight.zPosition = -1
        let nodes = [shell, head, frontLeft, frontRight, shadowLayer]
        for (node, part) in zip(nodes, parts) {
            let sprite = SKSpriteNode(texture: part.texture, size: part.bounds.size)
            sprite.position = CGPoint(x: part.bounds.midX, y: part.bounds.midY)
            node.addChild(sprite); addChild(node)
            tintables.append(sprite)
        }
        setScale(size / 122)
    }
    required init?(coder: NSCoder) { fatalError() }
    func applyDaylight(_ tint: UInt32, blend: CGFloat) {
        daylightBlend = blend
        for sprite in tintables {
            if blend > 0 { sprite.color = color(tint) }
            sprite.colorBlendFactor = blend
        }
    }
    func animate(time: Double, brain: TurtleBrain, speed: Double) {
        position = CGPoint(x: brain.x, y: brain.y); zRotation = brain.angle
        // 四肢划水前后错拍，换气时整体贴近水面变亮。
        let beat = time * (1.5 + speed * 0.9) + phase
        frontLeft.zRotation = sin(beat) * 0.4
        frontRight.zRotation = -sin(beat + 0.9) * 0.4
        backLeft.zRotation = sin(beat * 0.8 + 1.3) * 0.26
        backRight.zRotation = -sin(beat * 0.8 + 2.2) * 0.26
        head.position.x = 40 + sin(beat * 0.5) * 1.4
        shell.yScale = 1 + sin(beat) * 0.008
        alpha = brain.breathing ? 1 : 0.88
    }
}

final class TadpoleNode: SKNode {
    let sprite: SKSpriteNode
    private(set) var daylightBlend: CGFloat = 0
    let phase: Double
    init(variant: Int, size: Double) {
        let part = TadpolePainter.part(variant % 3)
        sprite = SKSpriteNode(texture: part.texture, size: part.bounds.size)
        phase = Double(variant) * 2.3 + Double(variant % 5)
        super.init()
        addChild(sprite)
        setScale(size)
    }
    required init?(coder: NSCoder) { fatalError() }
    func applyDaylight(_ tint: UInt32, blend: CGFloat) {
        daylightBlend = blend
        if blend > 0 { sprite.color = color(tint) }
        sprite.colorBlendFactor = blend
    }
    func animate(time: Double, brain: TadpoleBrain) {
        position = CGPoint(x: brain.x, y: brain.y); zRotation = brain.angle
        sprite.zRotation = sin(time * 7 + phase) * 0.3
        sprite.yScale = 1 + sin(time * 9 + phase) * 0.06
    }
}

final class SnailNode: SKNode {
    let sprite: SKSpriteNode
    private(set) var daylightBlend: CGFloat = 0
    let phase: Double
    init(variant: Int, size: Double) {
        let part = SnailPainter.part(variant % 2)
        sprite = SKSpriteNode(texture: part.texture, size: part.bounds.size)
        phase = Double(variant) * 2.9
        super.init()
        addChild(sprite)
        setScale(size)
    }
    required init?(coder: NSCoder) { fatalError() }
    func applyDaylight(_ tint: UInt32, blend: CGFloat) {
        daylightBlend = blend
        if blend > 0 { sprite.color = color(tint) }
        sprite.colorBlendFactor = blend
    }
    func animate(time: Double, brain: SnailBrain, moving: Bool) {
        position = CGPoint(x: brain.x, y: brain.y); zRotation = brain.angle
        // 爬行时身子一伸一缩，歇下时伏定。
        sprite.xScale = moving ? 1 + sin(time * 1.7 + phase) * 0.035 : 1
        sprite.zRotation = moving ? sin(time * 2.3 + phase) * 0.045 : 0
    }
}

// 池塘小居民的容器：生成、逐帧推进、时段染色与清理都在这里，
// 场景只负责在 configure/update 里调用。
final class PondCritters {
    struct Turtle { var brain: TurtleBrain; let node: TurtleNode }
    struct Tadpole { var brain: TadpoleBrain; let node: TadpoleNode }
    struct Snail { var brain: SnailBrain; let node: SnailNode }
    var turtles: [Turtle] = [], tadpoles: [Tadpole] = [], snails: [Snail] = []
    var rng = SeededRandom(state: 61103)
    var isEmpty: Bool { turtles.isEmpty && tadpoles.isEmpty && snails.isEmpty }

    func populateIfNeeded(world: CGSize, layer: SKNode) {
        guard turtles.isEmpty else { return }
        func spot(_ margin: Double) -> CGPoint {
            CGPoint(x: rng.range(margin, max(margin + 1, world.width - margin)),
                    y: rng.range(margin, max(margin + 1, world.height - margin)))
        }
        for i in 0..<2 {
            let at = spot(90)
            let brain = TurtleBrain(x: at.x, y: at.y, angle: rng.range(0, tau), cruise: rng.range(9, 14), phase: rng.range(0, tau))
            let node = TurtleNode(variant: i, size: rng.range(118, 150))
            node.position = at; node.zPosition = 0; layer.addChild(node)
            turtles.append(Turtle(brain: brain, node: node))
        }
        let area = world.width * world.height
        let tadpoleCount = Int(clamp(area / 170000, 4, 10))
        for i in 0..<tadpoleCount {
            let at = spot(40)
            let brain = TadpoleBrain(x: at.x, y: at.y, angle: rng.range(0, tau), cruise: rng.range(26, 40), phase: rng.range(0, tau))
            let node = TadpoleNode(variant: i % 3, size: rng.range(0.5, 0.72))
            node.position = at; node.zPosition = 1; layer.addChild(node)
            tadpoles.append(Tadpole(brain: brain, node: node))
        }
        let snailCount = Int(clamp(area / 780000, 1, 3))
        for i in 0..<snailCount {
            let at = spot(70)
            let brain = SnailBrain(x: at.x, y: at.y, angle: rng.range(0, tau), phase: rng.range(0, tau))
            let node = SnailNode(variant: i % 2, size: rng.range(0.85, 1.1))
            node.position = at; node.zPosition = -1; layer.addChild(node)
            snails.append(Snail(brain: brain, node: node))
        }
    }

    func remove() {
        guard !isEmpty else { return }
        for turtle in turtles { turtle.node.removeFromParent() }
        for tadpole in tadpoles { tadpole.node.removeFromParent() }
        for snail in snails { snail.node.removeFromParent() }
        turtles.removeAll(); tadpoles.removeAll(); snails.removeAll()
    }

    func rescale(xRatio: Double, yRatio: Double) {
        for i in turtles.indices {
            turtles[i].brain.x *= xRatio; turtles[i].brain.y *= yRatio
            turtles[i].node.position = CGPoint(x: turtles[i].brain.x, y: turtles[i].brain.y)
        }
        for i in tadpoles.indices {
            tadpoles[i].brain.x *= xRatio; tadpoles[i].brain.y *= yRatio
            tadpoles[i].node.position = CGPoint(x: tadpoles[i].brain.x, y: tadpoles[i].brain.y)
        }
        for i in snails.indices {
            snails[i].brain.x *= xRatio; snails[i].brain.y *= yRatio
            snails[i].node.position = CGPoint(x: snails[i].brain.x, y: snails[i].brain.y)
        }
    }

    func applyDaylight(_ daylight: Daylight) {
        for turtle in turtles { turtle.node.applyDaylight(daylight.tint, blend: daylight.fishBlend) }
        for tadpole in tadpoles { tadpole.node.applyDaylight(daylight.tint, blend: daylight.fishBlend) }
        for snail in snails { snail.node.applyDaylight(daylight.tint, blend: daylight.fishBlend) }
    }

    // 急挥惊散鱼群时，附近的蝌蚪也四散弹开；乌龟和田螺不为所动。
    func scatter(from point: CGPoint, at time: Double, radius: Double) {
        for i in tadpoles.indices where hypot(tadpoles[i].brain.x - point.x, tadpoles[i].brain.y - point.y) < radius {
            tadpoles[i].brain.startledUntil = time + 1.0
            tadpoles[i].brain.startledFrom = point
        }
    }

    func update(dt: Double, time: Double, width: Double, height: Double, speed: Double,
                targets: [CGPoint], reducedMotion: Bool, ripple: (CGPoint) -> Void) {
        for i in turtles.indices {
            if turtles[i].brain.step(dt: dt, time: time, width: width, height: height, speed: speed, targets: targets), !reducedMotion {
                ripple(CGPoint(x: turtles[i].brain.x, y: turtles[i].brain.y))
            }
            turtles[i].node.animate(time: time, brain: turtles[i].brain, speed: speed)
        }
        let positions = tadpoles.map { CGPoint(x: $0.brain.x, y: $0.brain.y) }
        var center = CGPoint.zero
        for p in positions { center.x += p.x; center.y += p.y }
        if !positions.isEmpty { center.x /= Double(positions.count); center.y /= Double(positions.count) }
        for i in tadpoles.indices {
            if time >= tadpoles[i].brain.nextDart {
                tadpoles[i].brain.dartUntil = time + rng.range(0.25, 0.6)
                tadpoles[i].brain.nextDart = time + rng.range(1.4, 4.5)
            }
            var neighbors: [CGPoint] = []
            neighbors.reserveCapacity(positions.count - 1)
            for (j, p) in positions.enumerated() where j != i { neighbors.append(p) }
            tadpoles[i].brain.step(dt: dt, time: time, width: width, height: height, speed: speed, center: center, neighbors: neighbors)
            tadpoles[i].node.animate(time: time, brain: tadpoles[i].brain)
        }
        for i in snails.indices {
            let moving = snails[i].brain.step(dt: dt, time: time, width: width, height: height, speed: speed, rng: &rng)
            snails[i].node.animate(time: time, brain: snails[i].brain, moving: moving)
        }
    }
}
