import AppKit
import SpriteKit

// 偶然到访池塘的小客人：蝴蝶飞进来绕花起舞、停在花朵上歇脚；燕子贴着水面高速掠过。
// 平时池塘里没有它们——到访结束即整体移除，纹理小而共享，开销可以忽略。
// 访客在水面之上飞行：本体画在浮叶与反光上方，投下的影子落在同一层、更淡更偏。

struct VisitorBrain {
    enum Kind { case butterfly, bird }
    enum Stage { case toFlower, hovering, exiting, crossing }
    let kind: Kind
    var x: Double, y: Double, angle: Double, speed: Double, phase: Double
    var stage: Stage
    var target: CGPoint
    var hoverUntil = 0.0
    var exitBy = 0.0
    var arriveBy = 0.0
    var wantSecondStop = false

    // 返回 true 表示这次到访结束，节点与影子应当移除。
    mutating func step(dt: Double, time: Double, width: Double, height: Double, flowers: [CGPoint], rng: inout SeededRandom) -> Bool {
        switch kind {
        case .bird:
            // 燕子一路贴水掠过，只带一点起伏，出界即离场。
            angle += sin(time * 0.9 + phase) * 0.3 * dt
            x += cos(angle) * speed * dt
            y += sin(angle) * speed * dt
            return x < -80 || x > width + 80 || y < -80 || y > height + 80
        case .butterfly:
            return stepButterfly(dt: dt, time: time, width: width, height: height, flowers: flowers, rng: &rng)
        }
    }

    private mutating func stepButterfly(dt: Double, time: Double, width: Double, height: Double, flowers: [CGPoint], rng: inout SeededRandom) -> Bool {
        let margin = 70.0
        switch stage {
        case .toFlower, .exiting:
            let dx = target.x - x, dy = target.y - y, d = hypot(dx, dy)
            // 飞行路径带一点摆动，不像巡导弹道。
            turnToward(atan2(dy, dx) + sin(time * 2.3 + phase) * 0.25, rate: 3.0, dt: dt)
            // 寻花末段减速：全速时转向半径 v/ω 达 17–25 像素，比 14 像素的落花判定圈还大，
            // 二次停靠改去近旁二三十像素内的花时会绕着花稳定盘旋、永远进不了圈。
            // 减速把半径缩进圈内，也贴近真实蝴蝶收翅落花的样子。
            let approach = stage == .toFlower ? max(0.25, min(1, d / 56)) : 1
            x += cos(angle) * speed * approach * dt
            y += sin(angle) * speed * approach * dt
            if stage == .toFlower {
                if d < 14 {
                    if wantSecondStop, flowers.count > 1 {
                        wantSecondStop = false
                        target = flowers[Int(rng.range(0, Double(flowers.count - 1)))]
                        arriveBy = time + hypot(target.x - x, target.y - y) / 35 + 12
                    } else {
                        stage = .hovering
                        hoverUntil = time + rng.range(2.5, 6)
                    }
                } else if time >= arriveBy {
                    // 保险丝：迟迟落不到花上（几何死锁、绕远）就就地悬停，随后按常路离场。
                    stage = .hovering
                    target = CGPoint(x: x, y: y)
                    hoverUntil = time + rng.range(2.5, 6)
                }
            }
            if stage == .exiting && (time >= exitBy || x < -margin || x > width + margin || y < -margin || y > height + margin) { return true }
        case .hovering:
            // 绕着花轻轻打转，飘远了就折回来。
            let dx = target.x - x, dy = target.y - y, d = hypot(dx, dy)
            if d > 24 { turnToward(atan2(dy, dx), rate: 2.5, dt: dt) }
            else { angle += sin(time * 1.1 + phase) * 1.4 * dt }
            x += cos(angle) * 10 * dt
            y += sin(angle) * 10 * dt
            if time >= hoverUntil {
                stage = .exiting
                speed = 62
                // 离场目标必须沿当前朝向真正出海：按对角线取距离，保证目标点必在窗外。
                // 若按宽高分别乘系数，对角朝向会把目标算进池内，蝴蝶抵达后在原地绕圈、
                // 永远满足不了出界条件（表现为一直在角落转圈）。
                let away = hypot(width, height) + 480
                target = CGPoint(x: x + cos(angle) * away, y: y + sin(angle) * away)
                exitBy = time + away / 25  // 保险丝：离场超时则强制结束到访
            }
        case .crossing:
            break
        }
        return false
    }

    private mutating func turnToward(_ desired: Double, rate: Double, dt: Double) {
        let delta = atan2(sin(desired - angle), cos(desired - angle))
        angle += clamp(delta, -rate * dt, rate * dt)
    }
}

protocol VisitorFlying: SKNode {
    func animate(time: Double, brain: VisitorBrain)
    func applyDaylight(_ tint: UInt32, blend: CGFloat)
}

// 翅根与身体中轴都过贴图局部原点；两翅贴图上下镜像后 bounds 不同，锚点须按各自 bounds 换算。
func rootAnchor(_ bounds: CGRect) -> CGPoint {
    CGPoint(x: -bounds.minX / bounds.width, y: -bounds.minY / bounds.height)
}

enum VisitorPainter {
    static var cache: [Int: [FishArtPart]] = [:]
    static var shadowCache: [Int: SKTexture] = [:]
    static let butterflyPalettes: [(base: UInt32, edge: UInt32, vein: UInt32, spot: UInt32)] = [
        (0xE08A3C, 0x5C3A1E, 0x9A5E28, 0xF2D8A8),  // 豹蛱蝶 · 橙
        (0xEFEAD8, 0x3C3C34, 0xBAB49C, 0x3C3C34),  // 粉蝶 · 白
        (0x6E8FC4, 0x27364E, 0x4C6890, 0xB8CCE8)   // 闪蝶 · 蓝
    ]
    // 翅膀按就位方向裁切:side = 1 在身体轴线上方,side = -1 上下镜像到下方。
    static let wingBounds = CGRect(x: -13, y: -2, width: 28, height: 29)
    static let wingBoundsMirrored = CGRect(x: -13, y: -27, width: 28, height: 29)
    static let butterflyBodyBounds = CGRect(x: -13, y: -4, width: 30, height: 8)
    static let birdWingBounds = CGRect(x: -15, y: -1.5, width: 22, height: 30)
    static let birdWingBoundsMirrored = CGRect(x: -15, y: -28.5, width: 22, height: 30)
    static let birdBodyBounds = CGRect(x: -17, y: -6.5, width: 36, height: 13)
    // 双翅与身体三块贴图，左右翅各画一份保证前后翅朝向对称。
    static func parts(_ kind: VisitorBrain.Kind, variant: Int) -> [FishArtPart] {
        let key = kind == .bird ? 100 : variant
        if let cached = cache[key] { return cached }
        let specs: [(CGRect, (CGContext) -> Void)]
        switch kind {
        case .butterfly:
            specs = [
                (wingBounds, { drawButterflyWing($0, side: 1, variant: variant % 3) }),
                (wingBoundsMirrored, { drawButterflyWing($0, side: -1, variant: variant % 3) }),
                (butterflyBodyBounds, { drawButterflyBody($0) })
            ]
        case .bird:
            specs = [
                (birdWingBounds, { drawBirdWing($0, side: 1) }),
                (birdWingBoundsMirrored, { drawBirdWing($0, side: -1) }),
                (birdBodyBounds, { drawBirdBody($0) })
            ]
        }
        let result = specs.map { bounds, drawing in FishArtPart(texture: SKTexture(cgImage: bitmap(bounds: bounds, scale: 4, draw: drawing)), bounds: bounds) }
        if cache.count > 12 { cache.removeAll() }
        cache[key] = result
        return result
    }
    static func shadow(_ kind: VisitorBrain.Kind) -> SKTexture {
        let key = kind == .bird ? 1 : 0
        if let cached = shadowCache[key] { return cached }
        let bounds = kind == .bird ? CGRect(x: -19, y: -11, width: 38, height: 22) : CGRect(x: -16, y: -12, width: 32, height: 24)
        let radius: Double = kind == .bird ? 14 : 11
        let texture = SKTexture(cgImage: bitmap(bounds: bounds, scale: 2) { ctx in
            var rng = SeededRandom(state: kind == .bird ? 7001 : 7002)
            fill(ctx, PondEnvironment.organic(center: .zero, radius: radius, random: &rng, count: 9), 0x071E18, alpha: 0.55)
        })
        shadowCache[key] = texture
        return texture
    }
    // 翅膀：前翅大、后翅小的两瓣，纯色底、深色缘、放射脉纹与斑点。
    // side 只镜像 y（翅膀展开方向），前翅始终朝头（+x），两翅分居身体两侧。
    static func drawButterflyWing(_ ctx: CGContext, side: Double, variant: Int) {
        let palette = butterflyPalettes[variant % butterflyPalettes.count]
        let hind = path { p in
            p.move(to: CGPoint(x: 1, y: side))
            p.addCurve(to: CGPoint(x: -6, y: side * 11), control1: CGPoint(x: -2, y: side * 5), control2: CGPoint(x: -5, y: side * 8.5))
            p.addCurve(to: CGPoint(x: 1, y: side * 15.5), control1: CGPoint(x: -6.5, y: side * 14), control2: CGPoint(x: -2, y: side * 16))
            p.addCurve(to: CGPoint(x: 2, y: side * 2), control1: CGPoint(x: 3, y: side * 10), control2: CGPoint(x: 3.4, y: side * 5))
            p.closeSubpath()
        }
        fill(ctx, hind, palette.base, alpha: 0.95)
        line(ctx, hind, palette.edge, width: 0.6, alpha: 0.75)
        let fore = path { p in
            p.move(to: CGPoint(x: 1, y: side))
            p.addCurve(to: CGPoint(x: 10, y: side * 19), control1: CGPoint(x: 6, y: side * 9), control2: CGPoint(x: 9, y: side * 15))
            p.addCurve(to: CGPoint(x: 13, y: side * 12), control1: CGPoint(x: 11, y: side * 18.5), control2: CGPoint(x: 12.5, y: side * 15))
            p.addCurve(to: CGPoint(x: 1.5, y: side * 2.5), control1: CGPoint(x: 9, y: side * 8), control2: CGPoint(x: 4, y: side * 4))
            p.closeSubpath()
        }
        fill(ctx, fore, palette.base)
        ctx.saveGState(); ctx.addPath(fore); ctx.clip()
        // 白粉蝶的前翅端斑更重，其余花色只淡淡压一角。
        var tipRandom = SeededRandom(state: 31)
        fill(ctx, PondEnvironment.organic(center: CGPoint(x: 9.5, y: side * 16), radius: variant == 1 ? 5 : 3.6, random: &tipRandom, count: 8), palette.edge, alpha: variant == 1 ? 0.85 : 0.4)
        var random = SeededRandom(state: UInt64(417 + variant * 97))
        for _ in 0..<7 {
            let at = CGPoint(x: random.range(2, 10), y: side * random.range(4, 15))
            ctx.setFillColor(color(palette.spot, random.range(0.5, 0.9)).cgColor)
            let r = random.range(0.5, 1.1)
            ctx.fillEllipse(in: CGRect(x: at.x - r, y: at.y - r, width: r * 2, height: r * 2))
        }
        ctx.restoreGState()
        line(ctx, fore, palette.edge, width: 0.7, alpha: 0.8)
        for i in 0..<4 {
            line(ctx, path { p in
                p.move(to: CGPoint(x: 1.5, y: side * 2))
                p.addQuadCurve(to: CGPoint(x: 3 + Double(i) * 3, y: side * (12 + Double(i) * 2.4)), control: CGPoint(x: 2 + Double(i) * 2.6, y: side * (6 + Double(i) * 2)))
            }, palette.vein, width: 0.5, alpha: 0.5)
        }
    }
    static func drawButterflyBody(_ ctx: CGContext) {
        for side in [-1.0, 1.0] {
            line(ctx, path { p in
                p.move(to: CGPoint(x: 9, y: side * 0.6))
                p.addQuadCurve(to: CGPoint(x: 15.5, y: side * 3.2), control: CGPoint(x: 12.5, y: side * 2.2))
            }, 0x3A3228, width: 0.7)
            ctx.setFillColor(color(0x3A3228).cgColor)
            ctx.fillEllipse(in: CGRect(x: 15, y: side * 3.2 - 0.8, width: 1.6, height: 1.6))
        }
        let body = ellipsePath(CGRect(x: -12, y: -2.1, width: 21.5, height: 4.2))
        fill(ctx, body, 0x4A4038)
        for x in [-6.0, -1.0, 4.0] {
            line(ctx, path { p in p.move(to: CGPoint(x: x, y: -1.9)); p.addQuadCurve(to: CGPoint(x: x, y: 1.9), control: CGPoint(x: x - 0.7, y: 0)) }, 0x2E2820, width: 0.45, alpha: 0.6)
        }
        ctx.setFillColor(color(0x37302A).cgColor)
        ctx.fillEllipse(in: CGRect(x: 7.4, y: -1.7, width: 3.4, height: 3.4))
        line(ctx, body, 0x2E2820, width: 0.4, alpha: 0.7)
    }
    // 燕子翼：细长后掠，后缘略浅，三根飞羽细线。side 镜像 y，两翼分居身体两侧、同向后掠。
    static func drawBirdWing(_ ctx: CGContext, side: Double) {
        let wing = path { p in
            p.move(to: CGPoint(x: 1, y: 0))
            p.addCurve(to: CGPoint(x: 3.5, y: side * 13), control1: CGPoint(x: 2.5, y: side * 5), control2: CGPoint(x: 3.5, y: side * 10))
            p.addCurve(to: CGPoint(x: -4, y: side * 27), control1: CGPoint(x: 3, y: side * 20), control2: CGPoint(x: 0.5, y: side * 24))
            p.addCurve(to: CGPoint(x: -12, y: side * 23), control1: CGPoint(x: -6, y: side * 28), control2: CGPoint(x: -9.5, y: side * 26.5))
            p.addCurve(to: CGPoint(x: -4, y: side * 5.5), control1: CGPoint(x: -10, y: side * 16), control2: CGPoint(x: -8, y: side * 10))
            p.addCurve(to: CGPoint(x: 1, y: 0), control1: CGPoint(x: -3, y: side * 3), control2: CGPoint(x: -0.5, y: side * 1.5))
            p.closeSubpath()
        }
        fill(ctx, wing, 0x4E5A64)
        ctx.saveGState(); ctx.addPath(wing); ctx.clip()
        ctx.translateBy(x: 1.5, y: side * -1.5)
        fill(ctx, wing, 0x78878F, alpha: 0.4)
        ctx.restoreGState()
        line(ctx, wing, 0x272F36, width: 0.6, alpha: 0.8)
        for i in 0..<3 {
            line(ctx, path { p in
                p.move(to: CGPoint(x: 1, y: side * (6 + Double(i) * 5)))
                p.addQuadCurve(to: CGPoint(x: -5 - Double(i) * 2, y: side * (19 + Double(i) * 2.5)), control: CGPoint(x: -1 - Double(i) * 1.5, y: side * (13 + Double(i) * 2.5)))
            }, 0x2E3840, width: 0.5, alpha: 0.5)
        }
    }
    // 燕子身体：流线躯干加剪式尾叉。
    static func drawBirdBody(_ ctx: CGContext) {
        let body = path { p in
            p.move(to: CGPoint(x: 17, y: 0))
            p.addCurve(to: CGPoint(x: -6, y: 2.6), control1: CGPoint(x: 10, y: 3), control2: CGPoint(x: -2, y: 3.4))
            p.addCurve(to: CGPoint(x: -15, y: 4.6), control1: CGPoint(x: -9, y: 2.2), control2: CGPoint(x: -12, y: 3.6))
            p.addCurve(to: CGPoint(x: -10.5, y: 0), control1: CGPoint(x: -12.5, y: 2), control2: CGPoint(x: -11, y: 1))
            p.addCurve(to: CGPoint(x: -15, y: -4.6), control1: CGPoint(x: -11, y: -1), control2: CGPoint(x: -12.5, y: -2))
            p.addCurve(to: CGPoint(x: -6, y: -2.6), control1: CGPoint(x: -12, y: -3.6), control2: CGPoint(x: -9, y: -2.2))
            p.addCurve(to: CGPoint(x: 17, y: 0), control1: CGPoint(x: -2, y: -3.4), control2: CGPoint(x: 10, y: -3))
            p.closeSubpath()
        }
        fill(ctx, body, 0x46525E)
        ctx.saveGState(); ctx.addPath(body); ctx.clip()
        fill(ctx, ellipsePath(CGRect(x: -14, y: -1.4, width: 26, height: 2.8)), 0x66727E, alpha: 0.45)
        fill(ctx, ellipsePath(CGRect(x: 11, y: -2.4, width: 5, height: 4.8)), 0x8B97A0, alpha: 0.55)
        ctx.restoreGState()
        line(ctx, body, 0x272F36, width: 0.55, alpha: 0.8)
    }
}

final class ButterflyNode: SKNode, VisitorFlying {
    let leftWing = SKNode(), rightWing = SKNode()
    private var tintables: [SKSpriteNode] = []
    private(set) var daylightBlend: CGFloat = 0
    let phase: Double
    init(variant: Int) {
        phase = Double(variant) * 1.9 + 0.4
        super.init()
        let parts = VisitorPainter.parts(.butterfly, variant: variant % 3)
        // 翅根锚在身体轴线上，收拢时两翅各自向轴线折合。
        for (node, part) in zip([leftWing, rightWing], [parts[0], parts[1]]) {
            let sprite = SKSpriteNode(texture: part.texture, size: part.bounds.size)
            sprite.anchorPoint = rootAnchor(part.bounds)
            node.addChild(sprite); addChild(node)
            tintables.append(sprite)
        }
        let body = SKSpriteNode(texture: parts[2].texture, size: parts[2].bounds.size)
        body.anchorPoint = rootAnchor(parts[2].bounds)
        addChild(body)
        tintables.append(body)
    }
    required init?(coder: NSCoder) { fatalError() }
    func applyDaylight(_ tint: UInt32, blend: CGFloat) {
        daylightBlend = blend
        for sprite in tintables {
            if blend > 0 { sprite.color = color(tint) }
            sprite.colorBlendFactor = blend
        }
    }
    func animate(time: Double, brain: VisitorBrain) {
        position = CGPoint(x: brain.x, y: brain.y)
        zRotation = brain.angle
        // 悬停时扇得慢，赶路时扇得急；收拢幅度朝 0 折向背部。
        let rate = brain.stage == .hovering ? 8.0 : 13.0
        let fold = 0.16 + 0.84 * abs(sin(time * rate + phase))
        leftWing.yScale = fold; rightWing.yScale = fold
    }
}

final class BirdNode: SKNode, VisitorFlying {
    let leftWing = SKNode(), rightWing = SKNode()
    private var tintables: [SKSpriteNode] = []
    private(set) var daylightBlend: CGFloat = 0
    let phase: Double
    override init() {
        phase = 1.1
        super.init()
        let parts = VisitorPainter.parts(.bird, variant: 0)
        for (node, part) in zip([leftWing, rightWing], [parts[0], parts[1]]) {
            let sprite = SKSpriteNode(texture: part.texture, size: part.bounds.size)
            sprite.anchorPoint = rootAnchor(part.bounds)
            node.addChild(sprite); addChild(node)
            tintables.append(sprite)
        }
        let body = SKSpriteNode(texture: parts[2].texture, size: parts[2].bounds.size)
        body.anchorPoint = rootAnchor(parts[2].bounds)
        addChild(body)
        tintables.append(body)
    }
    required init?(coder: NSCoder) { fatalError() }
    func applyDaylight(_ tint: UInt32, blend: CGFloat) {
        daylightBlend = blend
        for sprite in tintables {
            if blend > 0 { sprite.color = color(tint) }
            sprite.colorBlendFactor = blend
        }
    }
    func animate(time: Double, brain: VisitorBrain) {
        position = CGPoint(x: brain.x, y: brain.y)
        zRotation = brain.angle + sin(time * 2 + phase) * 0.05
        let fold = 0.3 + 0.7 * abs(sin(time * 4.6 + phase))
        leftWing.yScale = fold; rightWing.yScale = fold
    }
}

// 访客排期与推进：同一时刻至多一位客人，到访结束随机歇 35–90 秒；
// 夜晚蝴蝶与燕子都不出门。生成与移除是仅有的节点开销。
final class PondVisitors {
    struct Visit { var brain: VisitorBrain; let node: VisitorFlying; let shadow: SKSpriteNode }
    private(set) var visitor: Visit?
    var nextVisit: Double
    var rng = SeededRandom(state: 913247)
    private var daylight: Daylight = .noon
    var isEmpty: Bool { visitor == nil }

    init() {
        nextVisit = 8.0  // 首位客人别让池塘等太久
    }

    func update(dt: Double, time: Double, width: Double, height: Double, daylight: Daylight, flowers: [CGPoint], layer: SKNode) {
        self.daylight = daylight
        if let visit = visitor {
            var brain = visit.brain
            let done = brain.step(dt: dt, time: time, width: width, height: height, flowers: flowers, rng: &rng)
            visitor?.brain = brain
            if done {
                visit.node.removeFromParent(); visit.shadow.removeFromParent()
                visitor = nil
                nextVisit = time + rng.range(35, 90)
            } else {
                visit.node.position = CGPoint(x: brain.x, y: brain.y)
                visit.node.zRotation = brain.angle
                visit.node.animate(time: time, brain: brain)
                let offset: CGPoint = brain.kind == .bird ? CGPoint(x: 22, y: -30) : CGPoint(x: 11, y: -15)
                visit.shadow.position = CGPoint(x: brain.x + offset.x, y: brain.y + offset.y)
                visit.shadow.zRotation = brain.angle
            }
        } else if time >= nextVisit, daylight.key != "night", width > 120, height > 120 {
            spawn(time: time, width: width, height: height, flowers: flowers, layer: layer)
        }
    }

    func spawn(time: Double, width: Double, height: Double, flowers: [CGPoint], layer: SKNode, kind forced: VisitorBrain.Kind? = nil) {
        remove()
        let kind = forced ?? (rng.next() < 0.68 ? .butterfly : .bird)
        let shadow = SKSpriteNode(texture: VisitorPainter.shadow(kind))
        shadow.zPosition = 0
        shadow.alpha = kind == .bird ? 0.13 : 0.16
        if kind == .bird { shadow.setScale(1.15) }
        layer.addChild(shadow)
        let node: VisitorFlying
        var brain: VisitorBrain
        switch kind {
        case .butterfly:
            let entry = edgePoint(width: width, height: height)
            let target = flowers.isEmpty
                ? CGPoint(x: rng.range(width * 0.3, width * 0.7), y: rng.range(height * 0.3, height * 0.7))
                : flowers[min(flowers.count - 1, Int(rng.range(0, Double(flowers.count))))]
            brain = VisitorBrain(kind: .butterfly, x: entry.x, y: entry.y,
                                 angle: atan2(target.y - entry.y, target.x - entry.x),
                                 speed: rng.range(52, 75), phase: rng.range(0, tau),
                                 stage: .toFlower, target: target)
            brain.wantSecondStop = flowers.count > 1 && rng.next() < 0.45
            // 寻花保险丝按入场航程给足余量：巡航至少 52px/s，1/35 的倒数已含 30% 富余再加 12 秒兜绕。
            brain.arriveBy = time + hypot(target.x - entry.x, target.y - entry.y) / 35 + 12
            node = ButterflyNode(variant: Int(rng.range(0, 2.99)))
        case .bird:
            let fromLeft = rng.next() < 0.5
            let y0 = rng.range(height * 0.15, height * 0.85)
            let y1 = rng.range(height * 0.15, height * 0.85)
            let x0 = fromLeft ? -70.0 : width + 70.0
            let angle = atan2(y1 - y0, fromLeft ? width + 140 : -(width + 140))
            brain = VisitorBrain(kind: .bird, x: x0, y: y0, angle: angle,
                                 speed: rng.range(210, 280), phase: rng.range(0, tau),
                                 stage: .crossing, target: .zero)
            node = BirdNode()
        }
        node.zPosition = 1
        node.applyDaylight(daylight.tint, blend: daylight.fishBlend)
        layer.addChild(node)
        visitor = Visit(brain: brain, node: node, shadow: shadow)
    }

    func remove() {
        guard let visit = visitor else { return }
        visit.node.removeFromParent(); visit.shadow.removeFromParent()
        visitor = nil
    }

    func rescale(xRatio: Double, yRatio: Double) {
        guard var brain = visitor?.brain else { return }
        brain.x *= xRatio; brain.y *= yRatio
        brain.target = CGPoint(x: brain.target.x * xRatio, y: brain.target.y * yRatio)
        visitor?.brain = brain
        visitor?.node.position = CGPoint(x: brain.x, y: brain.y)
    }

    func applyDaylight(_ daylight: Daylight) {
        self.daylight = daylight
        visitor?.node.applyDaylight(daylight.tint, blend: daylight.fishBlend)
    }

    private func edgePoint(width: Double, height: Double) -> CGPoint {
        switch Int(rng.range(0, 3.99)) {
        case 0: return CGPoint(x: -60, y: rng.range(0, height))
        case 1: return CGPoint(x: width + 60, y: rng.range(0, height))
        case 2: return CGPoint(x: rng.range(0, width), y: -60)
        default: return CGPoint(x: rng.range(0, width), y: height + 60)
        }
    }
}
