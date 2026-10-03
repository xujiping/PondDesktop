import AppKit
import SpriteKit

// 纯色笔触组成光纹；只移动纹理坐标与几何，不使用渐变、模糊或辉光。
enum WaterArtwork {
    static let crest: SKTexture = {
        let image = bitmap(bounds: CGRect(x: -132, y: -132, width: 264, height: 264), scale: 2) { ctx in
            let contour = path { p in
                for i in 0...192 {
                    let a = Double(i) / 192 * tau
                    let r = 124 + sin(a * 3 + 0.4) * 1.2 + sin(a * 7) * 0.6
                    let point = CGPoint(x: cos(a) * r, y: sin(a) * r)
                    if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
                }
                p.closeSubpath()
            }
            ctx.saveGState(); ctx.translateBy(x: 0.6, y: -1.6)
            line(ctx, contour, 0x183E37, width: 2.4, alpha: 0.55); ctx.restoreGState()
            line(ctx, contour, 0xD9E8D2, width: 1.6, alpha: 0.8)
            // 水面朝光一侧的断续反光，不把整圈画成均匀白色。
            for (start, end) in [(0.25, 1.15), (1.5, 2.5), (3.5, 3.9), (5.3, 5.9)] {
                line(ctx, path { p in p.addArc(center: .zero, radius: 124, startAngle: start, endAngle: end, clockwise: false) },
                     0xEEF2DA, width: 2.1, alpha: 0.8)
            }
        }
        return SKTexture(cgImage: image)
    }()

    static let reflections: [SKTexture] = (0..<4).map { variant in
        var random = SeededRandom(state: UInt64(915871 + variant * 7919))
        let image = bitmap(bounds: CGRect(x: 0, y: 0, width: 180, height: 48), scale: 2) { ctx in
            // 每处只有几段短反光，保留大片没有线条的水域。
            for i in 0..<3 {
                let x = random.range(12, 60), y = 12 + Double(i) * 10, w = random.range(28, 80)
                let curve = path { p in
                    p.move(to: CGPoint(x: x, y: y))
                    p.addCurve(to: CGPoint(x: x + w, y: y + 1),
                               control1: CGPoint(x: x + w * 0.28, y: y + 3),
                               control2: CGPoint(x: x + w * 0.64, y: y - 3))
                }
                line(ctx, curve, 0xD5E6DE, width: random.range(0.7, 1.3), alpha: random.range(0.3, 0.6))
            }
        }
        return SKTexture(cgImage: image)
    }

}

final class WaterRipple: SKNode {
    let born: Double, lifetime: Double, radius: Double, strength: Double
    private let rings: [SKSpriteNode]
    init(at point: CGPoint, time: Double, radius: Double, strength: Double, reducedMotion: Bool) {
        born = time; lifetime = reducedMotion ? 2 : 5.6
        self.radius = radius; self.strength = strength
        rings = (0..<(reducedMotion ? 1 : strength < 0.3 ? 2 : 4)).map { _ in SKSpriteNode(texture: WaterArtwork.crest) }
        super.init(); position = point
        for ring in rings { addChild(ring) }
        advance(to: time)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @discardableResult func advance(to time: Double) -> Bool {
        let age = time - born
        for (index, ring) in rings.enumerated() {
            let progress = (age - Double(index) * 0.32) / lifetime
            ring.isHidden = progress < 0 || progress >= 1
            guard !ring.isHidden else { continue }
            let r = 9 + radius * pow(progress, 0.82)
            ring.size = CGSize(width: r * 2, height: r * 1.9)
            ring.alpha = strength * min(1, progress * 16) * pow(1 - progress, 1.4) * (1 - Double(index) * 0.14)
        }
        return age < lifetime + Double(rings.count - 1) * 0.32
    }
}

final class PondWater {
    let reflections = SKNode()
    private(set) var glints: [WaterGlint] = []
    let rippleLayer = SKNode()
    private(set) var ripples: [WaterRipple] = []
    private let clock = SKUniform(name: "u_waterTime", float: 0)
    private let refractionSize = SKUniform(name: "u_dimensions", vectorFloat2: SIMD2<Float>(1, 1))
    private let impulses = (0..<3).map { SKUniform(name: "u_impulse\($0)", vectorFloat4: SIMD4<Float>(0, 0, 0, 0)) }
    private var distance = 1.0
    private(set) var reducedMotion = false
    private(set) var daylight = Daylight.noon

    // 偏移量以屏幕点为单位；相机拉远后水纹不会缩水。
    private static let rippleDisplacement = """
        vec2 wave(vec2 p, vec4 impulse) {
            vec2 delta = p - impulse.xy;
            float distance = max(length(delta), 1.0);
            float front = distance - (9.0 + impulse.z * 37.0);
            float band = max(0.0, 1.0 - abs(front) / 32.0);
            float shift = sin(front * 0.19) * band * impulse.w * 5.0;
            return delta / distance * shift;
        }
        """
    private lazy var refraction = SKShader(source: Self.rippleDisplacement + """
        void main() {
            vec2 p = v_tex_coord * u_dimensions;
            float t = u_waterTime;
            vec2 bend = vec2(sin(p.y * 0.027 + t * 0.72) + sin((p.x + p.y) * 0.014 - t * 0.49),
                             cos(p.x * 0.023 + t * 0.57) + sin((p.y - p.x) * 0.018 + t * 0.61));
            bend = bend * 0.85 + wave(p, u_impulse0) + wave(p, u_impulse1) + wave(p, u_impulse2);
            vec2 uv = clamp(v_tex_coord + bend / u_dimensions, vec2(0.001), vec2(0.999));
            gl_FragColor = texture2D(u_texture, uv) * v_color_mix.a;
        }
        """, uniforms: [clock, refractionSize] + impulses)

    init() {
        reflections.zPosition = -2
        rippleLayer.zPosition = -1
    }

    func configure(size: CGSize, distance: Double, bed: SKSpriteNode, floor: SKNode, surface: SKNode, reducedMotion: Bool, daylight: Daylight = .noon) {
        self.distance = distance; self.reducedMotion = reducedMotion; self.daylight = daylight
        refractionSize.vectorFloat2Value = SIMD2(Float(size.width / distance), Float(size.height / distance))
        bed.shader = reducedMotion ? nil : refraction
        reflections.removeAllChildren(); glints.removeAll()
        let screenArea = size.width * size.height / (distance * distance)
        let count = min(12, max(4, Int(screenArea / 145000)))
        var random = SeededRandom(state: 871493)
        for i in 0..<count {
            let glint = WaterGlint(texture: WaterArtwork.reflections[i % 4],
                                   anchor: CGPoint(x: random.range(0.08, 0.92) * size.width,
                                                   y: random.range(0.08, 0.92) * size.height),
                                   phase: random.range(0, tau), distance: distance, daylight: daylight)
            reflections.addChild(glint.sprite); glints.append(glint)
            glint.update(time: 0)
        }
        if reflections.parent == nil { surface.addChild(reflections) }
        if rippleLayer.parent == nil { surface.addChild(rippleLayer) }
        // 改视野时清理旧坐标里的波纹，避免尺度突然跳变。
        rippleLayer.removeAllChildren(); ripples.removeAll()
        for impulse in impulses { impulse.vectorFloat4Value = .zero }
    }

    func addRipple(at point: CGPoint, time: Double, strength: Double = 0.62, radius: Double = 185) {
        if ripples.count >= 20 { ripples.removeFirst().removeFromParent() }
        let ripple = WaterRipple(at: point, time: time, radius: radius * distance, strength: strength, reducedMotion: reducedMotion)
        rippleLayer.addChild(ripple); ripples.append(ripple)
    }

    func update(time: Double) {
        if !reducedMotion {
            clock.floatValue = Float(time.truncatingRemainder(dividingBy: 3600))
            for glint in glints { glint.update(time: time) }
        }
        ripples.removeAll { ripple in
            if ripple.advance(to: time) { return false }
            ripple.removeFromParent(); return true
        }
        let recent = Array(ripples.suffix(3))
        for (index, impulse) in impulses.enumerated() {
            guard !reducedMotion, index < recent.count else { impulse.vectorFloat4Value = .zero; continue }
            let ripple = recent[index], age = time - ripple.born
            impulse.vectorFloat4Value = SIMD4(Float(ripple.position.x / distance), Float(ripple.position.y / distance),
                                             Float(age), Float(ripple.strength * max(0, 1 - age / ripple.lifetime)))
        }
    }

    func displacement(at point: CGPoint, time: Double) -> CGPoint {
        guard !reducedMotion else { return .zero }
        var offset = CGPoint.zero
        for ripple in ripples.suffix(3) {
            let dx = (point.x - ripple.position.x) / distance, dy = (point.y - ripple.position.y) / distance
            let d = max(1, hypot(dx, dy)), age = time - ripple.born
            let front = d - (9 + age * 37)
            let band = max(0, 1 - abs(front) / 32)
            let amount = sin(front * 0.19) * band * ripple.strength * max(0, 1 - age / ripple.lifetime) * 3 * distance
            offset.x += dx / d * amount; offset.y += dy / d * amount
        }
        return offset
    }
}

// 稀疏反光各自出现、变淡；位置只在小范围内漂移，不做全屏平铺。
// 光色随时段变化：中午保持纹理原色，夜晚月光偏冷、傍晚偏金。
struct WaterGlint {
    let sprite: SKSpriteNode
    let anchor: CGPoint, phase: Double, distance: Double
    private let alphaScale: Double
    init(texture: SKTexture, anchor: CGPoint, phase: Double, distance: Double, daylight: Daylight = .noon) {
        sprite = SKSpriteNode(texture: texture, size: CGSize(width: 160 * distance, height: 42 * distance))
        sprite.color = color(daylight.glow)
        sprite.colorBlendFactor = daylight.glintBlend
        alphaScale = daylight.glowAlpha
        self.anchor = anchor; self.phase = phase; self.distance = distance
    }
    func update(time: Double) {
        let t = time * 0.23 + phase
        sprite.position = CGPoint(x: anchor.x + sin(t * 0.7) * 9 * distance,
                                  y: anchor.y + sin(t * 0.83 + 1) * 4 * distance)
        sprite.zRotation = sin(t * 0.6) * 0.035
        sprite.alpha = (0.055 + 0.085 * pow((sin(t) + 1) / 2, 3)) * alphaScale
    }
}
