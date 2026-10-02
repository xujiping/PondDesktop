import AppKit
import SpriteKit

enum AquaticPlant: Int, CaseIterable {
    case lotus, lily, flower, reed, pondweed, duckweed
}

struct PlantPlacement {
    let kind: AquaticPlant
    let variant: Int
    let position: CGPoint
    let scale: CGFloat
    let rotation: CGFloat
    let submerged: Bool
    let order: CGFloat
}

struct PlantArt {
    let texture: SKTexture
    let bounds: CGRect
}

// Small, independently cached botanical plates keep their detail on Retina and wide displays.
// Light and shade are drawn with solid shapes and fine lines, never gradients or blur.
enum PlantPainter {
    static var cache: [Int: PlantArt] = [:]

    static func art(_ kind: AquaticPlant, variant: Int) -> PlantArt {
        let key = kind.rawValue * 10 + variant
        if let cached = cache[key] { return cached }
        let bounds: CGRect
        switch kind {
        case .lotus, .lily: bounds = CGRect(x: -120, y: -110, width: 240, height: 220)
        case .flower: bounds = CGRect(x: -78, y: -74, width: 156, height: 148)
        case .reed, .pondweed: bounds = CGRect(x: -140, y: -40, width: 280, height: 320)
        case .duckweed: bounds = CGRect(x: -50, y: -40, width: 100, height: 80)
        }
        let image = bitmap(bounds: bounds, scale: 4) { ctx in
            var rng = SeededRandom(state: UInt64(57319 + key * 7919))
            switch kind {
            case .lotus, .lily: leaf(ctx, lily: kind == .lily, variant: variant, random: &rng)
            case .flower: flower(ctx, variant: variant, random: &rng)
            case .reed: reeds(ctx, random: &rng)
            case .pondweed: pondweed(ctx, random: &rng)
            case .duckweed: duckweed(ctx, random: &rng)
            }
        }
        let texture = SKTexture(cgImage: image)
        texture.filteringMode = .linear
        let result = PlantArt(texture: texture, bounds: bounds)
        cache[key] = result
        return result
    }

    static func sprite(_ placement: PlantPlacement) -> SKSpriteNode {
        let art = art(placement.kind, variant: placement.variant)
        let sprite = SKSpriteNode(texture: art.texture, size: art.bounds.size)
        // Botanical plates use their stem/leaf center as the origin, including asymmetric grass.
        sprite.anchorPoint = CGPoint(x: -art.bounds.minX / art.bounds.width, y: -art.bounds.minY / art.bounds.height)
        sprite.position = placement.position
        sprite.setScale(placement.scale)
        sprite.zRotation = placement.rotation
        sprite.zPosition = placement.order
        return sprite
    }

    static func leaf(_ ctx: CGContext, lily: Bool, variant: Int, random: inout SeededRandom) {
        let rx = random.range(91, 103), ry = random.range(73, 88)
        let center = CGPoint(x: lily ? -5 : 3, y: lily ? -15 : -3)
        let start = lily ? 0.22 : 0.0, end = lily ? tau - 0.22 : tau
        var edge: [CGPoint] = []
        for i in 0...80 {
            let a = start + (end - start) * Double(i) / 80
            // A gently rippled margin replaces the old, deeply scalloped generic outline.
            let r = 1 + 0.016 * sin(a * 11 + Double(variant)) + 0.009 * sin(a * 23) + 0.026 * sin(a * 3 + 0.7)
            edge.append(CGPoint(x: cos(a) * rx * r, y: sin(a) * ry * r))
        }
        let outline = path { p in
            if lily { p.move(to: center); p.addQuadCurve(to: edge[0], control: CGPoint(x: 35, y: -7)) }
            else { p.move(to: edge[0]) }
            for point in edge.dropFirst() { p.addLine(to: point) }
            if lily { p.addQuadCurve(to: center, control: CGPoint(x: 38, y: -24)) }
            p.closeSubpath()
        }
        ctx.saveGState(); ctx.translateBy(x: 3, y: -5)
        fill(ctx, outline, 0x16372A, alpha: 0.28); ctx.restoreGState()
        let greens: [UInt32] = lily ? [0x416846, 0x597A47, 0x4A7042, 0x6E854B] : [0x66834F, 0x557D4B, 0x7D9157, 0x4D7346]
        fill(ctx, outline, greens[variant % greens.count])
        line(ctx, outline, 0x233F2B, width: 0.8, alpha: 0.6)
        ctx.saveGState(); ctx.addPath(outline); ctx.clip()
        // Uneven, interlocking patches give a matte leaf surface without smooth color ramps.
        for _ in 0..<55 {
            let at = CGPoint(x: random.range(-rx, rx), y: random.range(-ry, ry))
            let patch = PondEnvironment.organic(center: at, radius: random.range(4, 17), random: &random, count: 8)
            fill(ctx, patch, random.next() < 0.55 ? 0xBDD28A : 0x203D2A, alpha: random.range(0.025, 0.075))
        }
        let veinCount = lily ? 15 : 19
        for i in 0..<veinCount {
            let a = start + (end - start) * (Double(i) + 0.4) / Double(veinCount)
            let tip = CGPoint(x: cos(a) * rx * 0.97, y: sin(a) * ry * 0.97)
            let bend = random.range(-0.12, 0.12)
            let middle = CGPoint(x: center.x * 0.42 + cos(a + bend) * rx * 0.52, y: center.y * 0.42 + sin(a + bend) * ry * 0.52)
            let vein = path { p in p.move(to: center); p.addQuadCurve(to: tip, control: middle) }
            line(ctx, vein, 0x294B32, width: 1.65, alpha: 0.45)
            ctx.saveGState(); ctx.translateBy(x: -0.45, y: 0.6)
            line(ctx, vein, 0xC2CC89, width: 0.7, alpha: 0.67); ctx.restoreGState()
            // Secondary veins curve toward the next rib, with smaller connecting veinlets.
            for branch in 1...6 {
                let t = Double(branch) / 7
                let root = quadratic(center, middle, tip, t)
                for side in [-1.0, 1.0] {
                    let angle = a + side * 0.23 * (1 - t * 0.5)
                    let outer = CGPoint(x: cos(angle) * rx * min(0.97, t + 0.17), y: sin(angle) * ry * min(0.97, t + 0.17))
                    let control = CGPoint(x: root.x + cos(a + side * 0.8) * 12, y: root.y + sin(a + side * 0.8) * 10)
                    line(ctx, path { p in p.move(to: root); p.addQuadCurve(to: outer, control: control) }, 0xB1C382, width: 0.42, alpha: 0.36)
                    let fineRoot = quadratic(root, control, outer, 0.58)
                    line(ctx, path { p in p.move(to: fineRoot); p.addLine(to: CGPoint(x: fineRoot.x + cos(a) * 6, y: fineRoot.y + sin(a) * 5)) }, 0xC4CB91, width: 0.25, alpha: 0.25)
                }
            }
        }
        // Narrow broken rim highlights, a few age marks, and sharp water beads.
        for i in 0..<8 {
            let a = random.range(start, end), b = a + random.range(0.12, 0.38)
            line(ctx, path { p in
                p.move(to: CGPoint(x: cos(a) * rx * 0.97, y: sin(a) * ry * 0.97))
                p.addQuadCurve(to: CGPoint(x: cos(b) * rx * 0.97, y: sin(b) * ry * 0.97), control: CGPoint(x: cos((a + b) / 2) * rx, y: sin((a + b) / 2) * ry))
            }, i % 3 == 0 ? 0xB4A36C : 0xB2C385, width: random.range(0.6, 1.6), alpha: 0.6)
        }
        for _ in 0..<750 {
            let dot = random.range(0.18, 0.62)
            ctx.setFillColor(color(random.next() < 0.6 ? 0xD5D5A4 : 0x193D2B, random.range(0.06, 0.18)).cgColor)
            ctx.fillEllipse(in: CGRect(x: random.range(-rx, rx), y: random.range(-ry, ry), width: dot, height: dot))
        }
        if variant == 2 || variant == 3 {
            for _ in 0..<5 {
                let a = random.range(0, tau), r = random.range(0.72, 0.94)
                fill(ctx, PondEnvironment.organic(center: CGPoint(x: cos(a) * rx * r, y: sin(a) * ry * r), radius: random.range(1, 3), random: &random, count: 6), 0xA29350, alpha: 0.65)
            }
        }
        if !lily {
            ctx.setFillColor(color(0xCDD39B, 0.8).cgColor)
            ctx.fillEllipse(in: CGRect(x: center.x - 2.2, y: center.y - 1.7, width: 4.4, height: 3.4))
        }
        for _ in 0..<(variant % 3 + 1) {
            let x = random.range(-45, 48), y = random.range(-32, 40), r = random.range(1.8, 3.6)
            ctx.setFillColor(color(0x243F31, 0.75).cgColor); ctx.fillEllipse(in: CGRect(x: x - r, y: y - r - 0.8, width: r * 2, height: r * 1.5))
            ctx.setFillColor(color(0xDAE6CB, 0.7).cgColor); ctx.fillEllipse(in: CGRect(x: x - r * 0.65, y: y, width: r, height: r * 0.5))
        }
        ctx.restoreGState()
    }

    static func quadratic(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ t: Double) -> CGPoint {
        CGPoint(x: (1-t)*(1-t)*a.x + 2*(1-t)*t*b.x + t*t*c.x, y: (1-t)*(1-t)*a.y + 2*(1-t)*t*b.y + t*t*c.y)
    }

    static func flower(_ ctx: CGContext, variant: Int, random: inout SeededRandom) {
        ctx.setFillColor(color(0x18372A, 0.27).cgColor)
        ctx.fillEllipse(in: CGRect(x: -51, y: -48, width: 112, height: 91))
        let ivory = variant % 2 == 1
        for ring in 0..<4 {
            let count = [10, 11, 9, 7][ring]
            let length = 62 - Double(ring) * 11
            for i in 0..<count {
                ctx.saveGState()
                ctx.rotate(by: Double(i) / Double(count) * tau + Double(ring) * 0.31 + random.range(-0.055, 0.055))
                ctx.scaleBy(x: random.range(0.85, 1.05), y: random.range(0.9, 1.07))
                let petal = path { p in
                    p.move(to: CGPoint(x: -3, y: 2))
                    p.addCurve(to: CGPoint(x: 3, y: length), control1: CGPoint(x: -length * 0.34, y: length * 0.38), control2: CGPoint(x: -length * 0.2, y: length * 0.77))
                    p.addCurve(to: CGPoint(x: 4, y: 2), control1: CGPoint(x: length * 0.3, y: length * 0.72), control2: CGPoint(x: length * 0.3, y: length * 0.25))
                    p.closeSubpath()
                }
                let pink: [UInt32] = [0xB97587, 0xD393A2, 0xE7B7BF, 0xF1D7CD]
                let cream: [UInt32] = [0xB2B898, 0xD5D5B6, 0xE5E1C8, 0xF4EBD3]
                fill(ctx, petal, ivory ? cream[ring] : pink[ring])
                line(ctx, petal, ivory ? 0x858E6C : 0x9D6174, width: 0.7, alpha: 0.7)
                fill(ctx, path { p in
                    p.move(to: CGPoint(x: 3, y: 5)); p.addQuadCurve(to: CGPoint(x: 3, y: length), control: CGPoint(x: -4, y: length * 0.6))
                    p.addQuadCurve(to: CGPoint(x: 7, y: 12), control: CGPoint(x: 13, y: length * 0.65)); p.closeSubpath()
                }, ivory ? 0xFFF5DC : 0xFFE6DE, alpha: 0.38)
                for rib in -1...1 {
                    line(ctx, path { p in p.move(to: CGPoint(x: Double(rib) * 2, y: 9)); p.addQuadCurve(to: CGPoint(x: 3 + Double(rib) * 3, y: length * 0.85), control: CGPoint(x: Double(rib) * 7, y: length * 0.55)) }, ivory ? 0x93996D : 0xA86882, width: 0.35, alpha: 0.32)
                }
                ctx.restoreGState()
            }
        }
        for i in 0..<27 {
            let a = Double(i) / 27 * tau, r = random.range(9, 15)
            line(ctx, path { p in p.move(to: CGPoint(x: cos(a) * 5, y: sin(a) * 5)); p.addLine(to: CGPoint(x: cos(a) * r, y: sin(a) * r)) }, 0xC69C39, width: 1.1)
            ctx.setFillColor(color(0xF4D87A).cgColor); ctx.fillEllipse(in: CGRect(x: cos(a) * r - 1, y: sin(a) * r - 1, width: 2, height: 2))
        }
        ctx.setFillColor(color(0xD7BA5A).cgColor); ctx.fillEllipse(in: CGRect(x: -6, y: -6, width: 12, height: 12))
        for _ in 0..<12 {
            ctx.setFillColor(color(0x8D833C, 0.6).cgColor); ctx.fillEllipse(in: CGRect(x: random.range(-4, 4), y: random.range(-4, 4), width: 1.2, height: 1.2))
        }
    }

    static func reeds(_ ctx: CGContext, random: inout SeededRandom) {
        for i in 0..<9 {
            let height = random.range(130, 262), bend = random.range(-102, 102), w = random.range(4, 9)
            let base = CGPoint(x: random.range(-12, 12), y: random.range(-5, 9))
            let tip = CGPoint(x: bend, y: height)
            let first = CGPoint(x: Double(base.x) + bend * 0.2 - 18, y: height * 0.3)
            let second = CGPoint(x: bend * 0.55 + 24, y: height * 0.84)
            let blade = path { p in
                p.move(to: base); p.addCurve(to: tip, control1: first, control2: second)
                p.addCurve(to: CGPoint(x: base.x + w, y: base.y), control1: CGPoint(x: second.x + w * 0.7, y: second.y), control2: CGPoint(x: first.x + w, y: first.y)); p.closeSubpath()
            }
            fill(ctx, blade, i % 3 == 0 ? 0x6B8C50 : i % 3 == 1 ? 0x3F6F48 : 0x527D49, alpha: 0.83)
            line(ctx, path { p in p.move(to: CGPoint(x: base.x + w * 0.45, y: base.y)); p.addCurve(to: tip, control1: CGPoint(x: first.x + w * 0.45, y: first.y), control2: second) }, 0xACBA78, width: 0.7, alpha: 0.65)
            line(ctx, blade, 0x254E38, width: 0.55, alpha: 0.5)
        }
    }

    static func pondweed(_ ctx: CGContext, random: inout SeededRandom) {
        for stem in 0..<4 {
            ctx.saveGState(); ctx.rotate(by: Double(stem) * 0.23 - 0.35)
            let height = random.range(150, 235), bend = random.range(-30, 30)
            line(ctx, path { p in p.move(to: .zero); p.addQuadCurve(to: CGPoint(x: bend, y: height), control: CGPoint(x: -24, y: height * 0.5)) }, 0x446B3D, width: 2.1, alpha: 0.8)
            for node in 1..<14 {
                let t = Double(node) / 14, root = quadratic(.zero, CGPoint(x: -24, y: height * 0.5), CGPoint(x: bend, y: height), t)
                for side in [-1.0, 1.0] {
                    let l = random.range(15, 31) * (1.15 - t * 0.4)
                    let tip = CGPoint(x: root.x + side * l, y: root.y + random.range(10, 21))
                    let blade = path { p in
                        p.move(to: root); p.addQuadCurve(to: tip, control: CGPoint(x: root.x + side * l * 0.9, y: root.y - 4))
                        p.addQuadCurve(to: root, control: CGPoint(x: root.x + side * l * 0.65, y: tip.y + 6)); p.closeSubpath()
                    }
                    fill(ctx, blade, node % 3 == 0 ? 0x718D51 : 0x4E7D4A, alpha: 0.88)
                    line(ctx, path { p in p.move(to: root); p.addLine(to: tip) }, 0xB0BD7C, width: 0.5, alpha: 0.6)
                }
            }
            ctx.restoreGState()
        }
    }

    static func duckweed(_ ctx: CGContext, random: inout SeededRandom) {
        for _ in 0..<16 {
            let at = CGPoint(x: random.range(-38, 38), y: random.range(-27, 27)), r = random.range(2.5, 5.5)
            ctx.setFillColor(color(0x203F2E, 0.7).cgColor); ctx.fillEllipse(in: CGRect(x: at.x - r + 1, y: at.y - r - 1, width: r * 2, height: r * 1.45))
            ctx.setFillColor(color(random.next() < 0.5 ? 0x8CA65E : 0x6D924F).cgColor); ctx.fillEllipse(in: CGRect(x: at.x - r, y: at.y - r, width: r * 2, height: r * 1.45))
            line(ctx, path { p in p.move(to: CGPoint(x: at.x - r * 0.5, y: at.y - r * 0.2)); p.addLine(to: CGPoint(x: at.x + r * 0.5, y: at.y - r * 0.2)) }, 0xC1CF8B, width: 0.5, alpha: 0.6)
        }
    }
}
