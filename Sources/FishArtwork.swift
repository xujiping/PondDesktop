import AppKit
import SpriteKit

struct PaintPoint: Codable, Equatable { var x: Double; var y: Double }
struct PaintStroke: Codable, Equatable {
    var points: [PaintPoint]
    var color: UInt32
    var width: Double
    var erases: Bool = false
}
struct FishDesign: Codable, Equatable, Identifiable {
    var id: Int
    var name: String
    var bodyColor: UInt32
    var finColor: UInt32
    var variant: Int
    var size: Double = 1
    var strokes: [PaintStroke] = []
    static func initial(_ index: Int) -> FishDesign {
        let variant = index % 4
        return FishDesign(id: index, name: String(format: "金鱼 %02d", index + 1), bodyColor: variant == 1 ? 0xE8DDC4 : variant == 2 ? 0xCBA048 : 0xD97436, finColor: variant == 2 ? 0xDDBE70 : 0xE6A26A, variant: variant)
    }
    var artworkKey: Int {
        var h = Hasher(); h.combine(bodyColor); h.combine(finColor); h.combine(variant)
        for stroke in strokes { h.combine(stroke.color); h.combine(stroke.width); h.combine(stroke.erases); for point in stroke.points { h.combine(point.x); h.combine(point.y) } }
        return h.finalize()
    }
    var validated: FishDesign {
        var copy = self; copy.id = min(59, max(0, id)); copy.name = String(name.prefix(32))
        copy.bodyColor &= 0xFFFFFF; copy.finColor &= 0xFFFFFF; copy.variant = min(3, max(-1, variant))
        copy.size = size.isFinite ? clamp(size, 0.45, 2) : 1
        copy.strokes = Array(strokes.prefix(240)).compactMap { stroke in
            var s = stroke; s.width = s.width.isFinite ? clamp(s.width, 0.4, 12) : 3
            s.points = Array(s.points.filter { $0.x.isFinite && $0.y.isFinite }.prefix(1200))
            return s.points.isEmpty ? nil : s
        }
        return copy
    }
}
func fishBodyPath() -> CGPath {
    path { p in
        p.move(to: CGPoint(x: 41, y: 0))
        p.addCurve(to: CGPoint(x: -31, y: 0), control1: CGPoint(x: 40, y: 24), control2: CGPoint(x: -12, y: 23))
        p.addCurve(to: CGPoint(x: 41, y: 0), control1: CGPoint(x: -12, y: -23), control2: CGPoint(x: 40, y: -24)); p.closeSubpath()
    }
}
func fill(_ ctx: CGContext, _ p: CGPath, _ hex: UInt32, alpha: CGFloat = 1) {
    ctx.setFillColor(color(hex, alpha).cgColor); ctx.addPath(p); ctx.fillPath()
}
func line(_ ctx: CGContext, _ p: CGPath, _ hex: UInt32, width: CGFloat = 1, alpha: CGFloat = 1) {
    ctx.setStrokeColor(color(hex, alpha).cgColor); ctx.setLineWidth(width); ctx.addPath(p); ctx.strokePath()
}
func bitmap(bounds: CGRect, scale: CGFloat = 3, draw: (CGContext) -> Void) -> CGImage {
    let w = max(1, Int(ceil(bounds.width * scale))), h = max(1, Int(ceil(bounds.height * scale)))
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: scale, y: scale); ctx.translateBy(x: -bounds.minX, y: -bounds.minY)
    ctx.setLineCap(.round); ctx.setLineJoin(.round); draw(ctx)
    return ctx.makeImage()!
}

struct FishArtPart { let texture: SKTexture; let bounds: CGRect }
enum FishPainter {
    static var cache: [Int: [FishArtPart]] = [:]
    static let bodyBounds = CGRect(x: -34, y: -25, width: 79, height: 50)
    static let fullBounds = CGRect(x: -84, y: -42, width: 132, height: 84)
    static func parts(_ design: FishDesign) -> [FishArtPart] {
        let key = design.artworkKey
        if let cached = cache[key] { return cached }
        let specs: [(CGRect, (CGContext) -> Void)] = [
            (bodyBounds, { drawBody($0, design: design) }),
            (CGRect(x: -52, y: -32, width: 58, height: 64), { drawTail($0, design: design) }),
            (CGRect(x: -27, y: -2, width: 32, height: 36), { drawFin($0, design: design, side: 1) }),
            (CGRect(x: -27, y: -34, width: 32, height: 36), { drawFin($0, design: design, side: -1) }),
            (bodyBounds, { fill($0, fishBodyPath(), 0x08251D, alpha: 0.25) })
        ]
        // One shared texture set per artwork key: identical fish reuse GPU memory instead of
        // uploading a private copy per node.
        let result = specs.map { bounds, drawing in FishArtPart(texture: SKTexture(cgImage: bitmap(bounds: bounds, scale: 4, draw: drawing)), bounds: bounds) }
        if cache.count > 24 { cache.removeAll() }
        cache[key] = result; return result
    }
    static func drawBody(_ ctx: CGContext, design: FishDesign) {
        let body = fishBodyPath()
        fill(ctx, body, design.bodyColor)
        ctx.saveGState(); ctx.addPath(body); ctx.clip()
        // The pattern occupies its own layer so the eraser reveals the original body color.
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        if design.variant == 1 {
            fill(ctx, path { p in p.move(to: CGPoint(x: 30, y: 14)); p.addCurve(to: CGPoint(x: 8, y: -17), control1: CGPoint(x: -1, y: 18), control2: CGPoint(x: 34, y: -11)); p.addCurve(to: CGPoint(x: 30, y: 14), control1: CGPoint(x: -16, y: -20), control2: CGPoint(x: -12, y: 15)); p.closeSubpath() }, 0xC96B35)
            ctx.setFillColor(color(0xC96B35).cgColor); ctx.fillEllipse(in: CGRect(x: -22, y: -10, width: 20, height: 21))
        } else if design.variant == 3 {
            fill(ctx, path { p in p.move(to: CGPoint(x: 19, y: 17)); p.addCurve(to: CGPoint(x: 7, y: -18), control1: CGPoint(x: -6, y: 24), control2: CGPoint(x: 33, y: -15)); p.addCurve(to: CGPoint(x: -8, y: 17), control1: CGPoint(x: -20, y: -17), control2: CGPoint(x: 3, y: 10)); p.closeSubpath() }, 0xE8DFCE)
        }
        for stroke in design.strokes {
            guard let first = stroke.points.first else { continue }
            ctx.setBlendMode(stroke.erases ? .clear : .normal)
            ctx.setStrokeColor(color(stroke.color).cgColor); ctx.setFillColor(color(stroke.color).cgColor); ctx.setLineWidth(stroke.width)
            if stroke.points.count == 1 { ctx.fillEllipse(in: CGRect(x: first.x - stroke.width / 2, y: first.y - stroke.width / 2, width: stroke.width, height: stroke.width)) }
            else {
                ctx.beginPath(); ctx.move(to: CGPoint(x: first.x, y: first.y))
                for point in stroke.points.dropFirst() { ctx.addLine(to: CGPoint(x: point.x, y: point.y)) }
                ctx.strokePath()
            }
        }
        ctx.setBlendMode(.normal); ctx.endTransparencyLayer()
        // Discrete contour shapes, scale arcs and a fine stipple provide material detail; no gradients.
        fill(ctx, path { p in p.move(to: CGPoint(x: -31, y: 0)); p.addCurve(to: CGPoint(x: 40, y: -2), control1: CGPoint(x: -10, y: -24), control2: CGPoint(x: 35, y: -24)); p.addCurve(to: CGPoint(x: -31, y: 0), control1: CGPoint(x: 26, y: -12), control2: CGPoint(x: -4, y: -15)); p.closeSubpath() }, 0x493527, alpha: 0.10)
        var random = SeededRandom(state: 71823)
        for _ in 0..<100 {
            let r = random.range(0.09, 0.3)
            ctx.setFillColor(color(0xFFF0CC, random.range(0.04, 0.16)).cgColor)
            ctx.fillEllipse(in: CGRect(x: random.range(-27, 37), y: random.range(-17, 17), width: r, height: r))
        }
        for column in 0..<8 {
            let x = Double(column) * 5.8 - 20
            for row in -2...2 {
                let y = Double(row) * 5.2 + (column % 2 == 0 ? 0 : 2.6)
                line(ctx, path { p in p.move(to: CGPoint(x: x, y: y - 2)); p.addQuadCurve(to: CGPoint(x: x, y: y + 2), control: CGPoint(x: x - 3.7, y: y)) }, 0x765438, width: 0.42, alpha: 0.26)
                line(ctx, path { p in p.move(to: CGPoint(x: x + 0.7, y: y - 1.7)); p.addQuadCurve(to: CGPoint(x: x + 0.7, y: y + 1.7), control: CGPoint(x: x - 2.6, y: y)) }, 0xFFF0C6, width: 0.35, alpha: 0.3)
            }
        }
        ctx.restoreGState()
        line(ctx, body, 0x6C4C35, width: 0.55, alpha: 0.65)
        line(ctx, path { p in p.move(to: CGPoint(x: 23, y: -12)); p.addQuadCurve(to: CGPoint(x: 23, y: 12), control: CGPoint(x: 17, y: 0)) }, 0x835137, width: 0.65, alpha: 0.5)
        line(ctx, path { p in p.move(to: CGPoint(x: -18, y: 1)); p.addQuadCurve(to: CGPoint(x: 17, y: 1), control: CGPoint(x: -1, y: 4)) }, 0xF1D7A6, width: 1.2, alpha: 0.4)
        for y in [-8.5, 8.5] {
            ctx.setFillColor(color(0x3B3224).cgColor); ctx.fillEllipse(in: CGRect(x: 30, y: y - 1.65, width: 3.8, height: 3.3))
            ctx.setFillColor(color(0xF9EBCF).cgColor); ctx.fillEllipse(in: CGRect(x: 31.5, y: y - 0.2, width: 0.9, height: 0.9))
        }
    }
    static func drawTail(_ ctx: CGContext, design: FishDesign) {
        let p = path { p in p.move(to: .zero); p.addCurve(to: CGPoint(x: -45, y: 28), control1: CGPoint(x: -17, y: 5), control2: CGPoint(x: -19, y: 30)); p.addCurve(to: CGPoint(x: -32, y: 0), control1: CGPoint(x: -54, y: 10), control2: CGPoint(x: -40, y: 10)); p.addCurve(to: CGPoint(x: -45, y: -28), control1: CGPoint(x: -40, y: -10), control2: CGPoint(x: -54, y: -10)); p.addCurve(to: .zero, control1: CGPoint(x: -19, y: -30), control2: CGPoint(x: -17, y: -5)); p.closeSubpath() }
        fill(ctx, p, design.finColor, alpha: 0.83); line(ctx, p, 0x8B6343, width: 0.5, alpha: 0.45)
        for i in -5...5 {
            let y = Double(i) * 5.2, x = -42.0 + 7 * (1 - abs(Double(i)) / 5)
            line(ctx, path { p in p.move(to: .zero); p.addQuadCurve(to: CGPoint(x: x, y: y), control: CGPoint(x: -19, y: y * 0.25)) }, 0x78593F, width: 0.35, alpha: 0.36)
        }
    }
    static func drawFin(_ ctx: CGContext, design: FishDesign, side: Double) {
        let p = path { p in p.move(to: .zero); p.addCurve(to: CGPoint(x: -21, y: side * 24), control1: CGPoint(x: -1, y: side * 20), control2: CGPoint(x: -12, y: side * 30)); p.addQuadCurve(to: .zero, control: CGPoint(x: -23, y: side * 6)); p.closeSubpath() }
        fill(ctx, p, design.finColor, alpha: 0.67); line(ctx, p, 0x765F3E, width: 0.45, alpha: 0.4)
        for i in 1...5 { line(ctx, path { p in p.move(to: .zero); p.addLine(to: CGPoint(x: -Double(i) * 3.5, y: side * (22 - Double(i)))) }, 0x776242, width: 0.3, alpha: 0.36) }
    }
    static func drawWhole(_ ctx: CGContext, design: FishDesign) {
        ctx.saveGState(); ctx.translateBy(x: -27, y: 0); drawTail(ctx, design: design); ctx.restoreGState()
        for side in [1.0, -1.0] { ctx.saveGState(); ctx.translateBy(x: 12, y: side * 12); drawFin(ctx, design: design, side: side); ctx.restoreGState() }
        drawBody(ctx, design: design)
    }
}

final class FishNode: SKNode {
    let tail = SKNode(), leftFin = SKNode(), rightFin = SKNode(), body = SKNode(), shadowLayer = SKNode()
    let designKey: Int
    init(index: Int, design: FishDesign, size: Double) {
        designKey = design.artworkKey
        super.init()
        tail.position.x = -27; leftFin.position = CGPoint(x: 12, y: 12); rightFin.position = CGPoint(x: 12, y: -12)
        shadowLayer.position = CGPoint(x: 5, y: -8); shadowLayer.zPosition = -3
        tail.zPosition = -1; leftFin.zPosition = -1; rightFin.zPosition = -1
        let nodes = [body, tail, leftFin, rightFin, shadowLayer]
        for (node, part) in zip(nodes, FishPainter.parts(design)) {
            let sprite = SKSpriteNode(texture: part.texture, size: part.bounds.size)
            sprite.position = CGPoint(x: part.bounds.midX, y: part.bounds.midY); node.addChild(sprite); addChild(node)
        }
        setScale(size / 115 * design.size)
    }
    required init?(coder: NSCoder) { fatalError() }
    func animate(time: Double, swimmer: Swimmer, speed: Double) {
        position = CGPoint(x: swimmer.x, y: swimmer.y); zRotation = swimmer.angle
        let beat = time * (3.8 + speed * 1.4) + swimmer.phase
        tail.zRotation = sin(beat) * 0.3 - swimmer.turn * 0.15
        leftFin.zRotation = sin(beat * 0.8) * 0.18; rightFin.zRotation = -sin(beat * 0.8 + 0.6) * 0.18
        body.yScale = 1 + sin(beat) * 0.012
    }
}
