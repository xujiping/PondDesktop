import AppKit

// Organic outlines, fine noise and discrete material marks. All colors are solid fills.
enum PondEnvironment {
    static func make(size: CGSize, density: Double, palette: Palette) -> (CGImage, CGImage) {
        let scale = min(1.4, 3000 / max(size.width, size.height))
        let bounds = CGRect(origin: .zero, size: size)
        let anchors = [CGPoint(x: size.width * 0.92, y: size.height * 0.86), CGPoint(x: size.width * 0.065, y: size.height * 0.13), CGPoint(x: size.width * 0.94, y: size.height * 0.035), CGPoint(x: size.width * 0.015, y: size.height * 0.77)]
        let bed = bitmap(bounds: bounds, scale: scale) { ctx in
            ctx.setFillColor(color(palette.water).cgColor); ctx.fill(bounds)
            var rng = SeededRandom(state: 182954)
            // Irregular silt islands, rather than repeating round background blobs.
            for _ in 0..<210 {
                let center = CGPoint(x: rng.range(0, size.width), y: rng.range(0, size.height)), r = rng.range(16, 125)
                let island = organic(center: center, radius: r, random: &rng)
                fill(ctx, island, rng.next() < 0.5 ? palette.silt : 0x273F30, alpha: rng.range(0.025, 0.08))
            }
            let grains = min(75000, Int(size.width * size.height / 42))
            for _ in 0..<grains {
                let r = rng.range(0.25, 1.05)
                ctx.setFillColor(color(rng.next() < 0.58 ? 0xBDBDA1 : 0x213F31, rng.range(0.04, 0.15)).cgColor)
                ctx.fill(CGRect(x: rng.range(0, size.width), y: rng.range(0, size.height), width: r, height: r * 0.7))
            }
            for _ in 0..<480 {
                let x = rng.range(0, size.width), y = rng.range(0, size.height), r = rng.range(1.2, 7)
                pebble(ctx, at: CGPoint(x: x, y: y), radius: r, random: &rng, alpha: 0.32)
            }
            for (cluster, anchor) in anchors.enumerated() {
                for _ in 0..<Int(55 * density) {
                    let angle = rng.range(0, tau), distance = rng.range(0, 175)
                    pebble(ctx, at: CGPoint(x: anchor.x + cos(angle) * distance, y: anchor.y + sin(angle) * distance * 0.72), radius: rng.range(6, 22), random: &rng, alpha: 0.52)
                }
                for i in 0..<Int(19 * density) {
                    let base = CGPoint(x: anchor.x + rng.range(-110, 95), y: anchor.y + rng.range(-90, 60))
                    ctx.saveGState(); ctx.translateBy(x: base.x, y: base.y); ctx.rotate(by: rng.range(-1.8, 1.8))
                    if i % 3 == 0 { elodea(ctx, length: rng.range(65, 150), random: &rng) }
                    else { ribbonGrass(ctx, length: rng.range(70, 185), random: &rng) }
                    ctx.restoreGState()
                }
                if cluster < 3 {
                    ctx.saveGState(); ctx.translateBy(x: anchor.x - 65, y: anchor.y - 60); ctx.rotate(by: rng.range(-1, 1))
                    rhizome(ctx, random: &rng); ctx.restoreGState()
                }
                // Thin submerged lotus stalks radiate from their rhizome.
                for _ in 0..<Int(8 * density) {
                    let end = CGPoint(x: anchor.x + rng.range(-165, 165), y: anchor.y + rng.range(-135, 115))
                    line(ctx, path { p in p.move(to: CGPoint(x: anchor.x - 35, y: anchor.y - 45)); p.addQuadCurve(to: end, control: CGPoint(x: anchor.x + 60, y: end.y - 20)) }, 0x3B5933, width: 2.2, alpha: 0.45)
                }
            }
            // A few broken sunlit water contours, with uniform stroke color.
            for _ in 0..<26 {
                let x = rng.range(0, size.width), y = rng.range(0, size.height), width = rng.range(55, 180)
                line(ctx, path { p in p.move(to: CGPoint(x: x, y: y)); p.addCurve(to: CGPoint(x: x + width, y: y + 18), control1: CGPoint(x: x + width * 0.3, y: y + 35), control2: CGPoint(x: x + width * 0.55, y: y - 35)) }, 0xD3D8AB, width: 0.8, alpha: 0.07)
            }
        }
        let plants = bitmap(bounds: bounds, scale: scale) { ctx in
            var rng = SeededRandom(state: 395177)
            for (cluster, anchor) in anchors.enumerated() {
                let count = Int((cluster < 2 ? 12 : 7) * density)
                for i in 0..<count {
                    let angle = rng.range(0, tau), d = rng.range(20, cluster < 2 ? 165 : 135)
                    let position = CGPoint(x: anchor.x + cos(angle) * d, y: anchor.y + sin(angle) * d * 0.74)
                    ctx.saveGState(); ctx.translateBy(x: position.x, y: position.y); ctx.rotate(by: rng.range(0, tau))
                    lotusLeaf(ctx, radius: rng.range(25, 63), palette: palette, random: &rng, young: i % 5 == 0)
                    if i == 2 || (cluster < 2 && i == 7) { ctx.translateBy(x: 23, y: 18); lotusFlower(ctx, radius: rng.range(20, 27), random: &rng) }
                    if i == 5 { ctx.translateBy(x: 26, y: 5); seedPod(ctx) }
                    ctx.restoreGState()
                }
                for _ in 0..<Int(36 * density) {
                    let x = anchor.x + rng.range(-210, 200), y = anchor.y + rng.range(-170, 155), r = rng.range(1.4, 3.4)
                    ctx.setFillColor(color(0x87A555, 0.75).cgColor); ctx.fillEllipse(in: CGRect(x: x, y: y, width: r * 2, height: r * 1.3))
                }
            }
        }
        return (bed, plants)
    }
    static func organic(center: CGPoint, radius: Double, random: inout SeededRandom, count: Int = 18) -> CGPath {
        var points: [CGPoint] = []
        for i in 0..<count { let a = Double(i) / Double(count) * tau, r = radius * random.range(0.78, 1.15); points.append(CGPoint(x: center.x + cos(a) * r, y: center.y + sin(a) * r * 0.78)) }
        return path { p in
            let first = CGPoint(x: (points[0].x + points[count - 1].x) / 2, y: (points[0].y + points[count - 1].y) / 2)
            p.move(to: first)
            for i in 0..<count { let next = points[(i + 1) % count]; p.addQuadCurve(to: CGPoint(x: (points[i].x + next.x) / 2, y: (points[i].y + next.y) / 2), control: points[i]) }
            p.closeSubpath()
        }
    }
    static func pebble(_ ctx: CGContext, at center: CGPoint, radius: Double, random: inout SeededRandom, alpha: Double) {
        let p = organic(center: center, radius: radius, random: &random, count: 9)
        ctx.saveGState(); ctx.translateBy(x: 2, y: -2); fill(ctx, p, 0x183D32, alpha: alpha * 0.6); ctx.restoreGState()
        let shades: [UInt32] = [0x849181, 0x6D8171, 0xA5A28A, 0x5E7469, 0x8C8B72]
        fill(ctx, p, shades[Int(random.range(0, 4.99))], alpha: alpha)
        line(ctx, path { p in p.move(to: CGPoint(x: center.x - radius * 0.5, y: center.y + radius * 0.36)); p.addQuadCurve(to: CGPoint(x: center.x + radius * 0.45, y: center.y + radius * 0.36), control: CGPoint(x: center.x, y: center.y + radius * 0.68)) }, 0xD8CFAB, width: max(0.45, radius / 12), alpha: alpha * 0.4)
    }
    static func ribbonGrass(_ ctx: CGContext, length: Double, random: inout SeededRandom) {
        for i in 0..<5 {
            let h = length * random.range(0.6, 1.2), bend = random.range(-55, 55), width = random.range(3, 6)
            let p = path { p in p.move(to: .zero); p.addCurve(to: CGPoint(x: bend, y: h), control1: CGPoint(x: -20, y: h * 0.3), control2: CGPoint(x: 35, y: h * 0.75)); p.addCurve(to: CGPoint(x: width, y: 0), control1: CGPoint(x: 25, y: h * 0.75), control2: CGPoint(x: -12, y: h * 0.3)); p.closeSubpath() }
            fill(ctx, p, i % 2 == 0 ? 0x547C49 : 0x365C3B, alpha: 0.53)
            line(ctx, path { p in p.move(to: CGPoint(x: width * 0.5, y: 0)); p.addCurve(to: CGPoint(x: bend, y: h), control1: CGPoint(x: -16, y: h * 0.3), control2: CGPoint(x: 30, y: h * 0.75)) }, 0x91AB68, width: 0.6, alpha: 0.35)
        }
    }
    static func elodea(_ ctx: CGContext, length: Double, random: inout SeededRandom) {
        let bend = random.range(-35, 35)
        line(ctx, path { p in p.move(to: .zero); p.addQuadCurve(to: CGPoint(x: bend, y: length), control: CGPoint(x: -20, y: length * 0.5)) }, 0x4E743D, width: 1.5, alpha: 0.67)
        for i in 1..<12 {
            let y = Double(i) / 12 * length, x = bend * pow(Double(i) / 12, 2) - 8 * sin(Double(i) / 12 * .pi)
            for side in [-1.0, 1.0] {
                let tip = CGPoint(x: x + side * random.range(9, 18), y: y + random.range(8, 17))
                fill(ctx, path { p in p.move(to: CGPoint(x: x, y: y)); p.addQuadCurve(to: tip, control: CGPoint(x: x + side * 14, y: y)); p.addQuadCurve(to: CGPoint(x: x, y: y), control: CGPoint(x: x + side * 2, y: y + 13)); p.closeSubpath() }, 0x5D824B, alpha: 0.55)
            }
        }
    }
    static func rhizome(_ ctx: CGContext, random: inout SeededRandom) {
        for i in 0..<3 {
            let x = Double(i) * 48, y = sin(Double(i) * 1.7) * 10
            let p = path { p in p.move(to: CGPoint(x: x, y: y)); p.addCurve(to: CGPoint(x: x + 50, y: y + 2), control1: CGPoint(x: x + 8, y: y + 18), control2: CGPoint(x: x + 43, y: y + 17)); p.addCurve(to: CGPoint(x: x, y: y), control1: CGPoint(x: x + 47, y: y - 16), control2: CGPoint(x: x + 6, y: y - 15)); p.closeSubpath() }
            fill(ctx, p, 0xA49A6B, alpha: 0.47); line(ctx, p, 0x5D603C, width: 0.8, alpha: 0.45)
            for j in 1...3 { let sx = x + Double(j) * 12; line(ctx, path { p in p.move(to: CGPoint(x: sx, y: y - 8)); p.addQuadCurve(to: CGPoint(x: sx, y: y + 9), control: CGPoint(x: sx - 3, y: y)) }, 0x646C43, width: 0.6, alpha: 0.48) }
            for j in 0..<4 { let sx = x + Double(j) * 7; line(ctx, path { p in p.move(to: CGPoint(x: sx, y: y - 10)); p.addQuadCurve(to: CGPoint(x: sx - random.range(8, 22), y: y - random.range(17, 35)), control: CGPoint(x: sx + 4, y: y - 21)) }, 0xA79C70, width: 0.65, alpha: 0.38) }
        }
    }
    static func lotusLeaf(_ ctx: CGContext, radius r: Double, palette: Palette, random: inout SeededRandom, young: Bool) {
        let outline = organic(center: .zero, radius: r, random: &random, count: 30)
        ctx.saveGState(); ctx.translateBy(x: 4, y: -7); fill(ctx, outline, 0x102F23, alpha: 0.3); ctx.restoreGState()
        fill(ctx, outline, young ? 0x7D9552 : palette.leaf)
        line(ctx, outline, 0x344D2D, width: 0.9, alpha: 0.8)
        ctx.saveGState(); ctx.addPath(outline); ctx.clip()
        for sector in 0..<12 {
            let a = Double(sector) / 12 * tau
            if sector % 3 == 0 { fill(ctx, path { p in p.move(to: .zero); p.addLine(to: CGPoint(x: cos(a) * r, y: sin(a) * r)); p.addLine(to: CGPoint(x: cos(a + 0.28) * r, y: sin(a + 0.28) * r)); p.closeSubpath() }, 0x273F24, alpha: 0.08) }
            let end = CGPoint(x: cos(a) * r * 0.94, y: sin(a) * r * 0.75)
            line(ctx, path { p in p.move(to: .zero); p.addQuadCurve(to: end, control: CGPoint(x: cos(a + 0.11) * r * 0.53, y: sin(a + 0.11) * r * 0.42)) }, 0xAFBD77, width: 0.65, alpha: 0.6)
            for branch in 1...4 {
                let t = Double(branch) / 5, center = CGPoint(x: end.x * t, y: end.y * t)
                for sign in [-1.0, 1.0] {
                    let tip = CGPoint(x: center.x + cos(a + sign * 0.65) * r * 0.2, y: center.y + sin(a + sign * 0.65) * r * 0.16)
                    line(ctx, path { p in p.move(to: center); p.addLine(to: tip) }, 0xABB979, width: 0.3, alpha: 0.42)
                }
            }
        }
        for _ in 0..<240 {
            let x = random.range(-r, r), y = random.range(-r, r), dot = random.range(0.2, 0.7)
            ctx.setFillColor(color(random.next() < 0.5 ? 0xD7D9A3 : 0x273F26, random.range(0.08, 0.24)).cgColor); ctx.fillEllipse(in: CGRect(x: x, y: y, width: dot, height: dot))
        }
        ctx.restoreGState()
        ctx.setFillColor(color(0xB4C085, 0.5).cgColor); ctx.fillEllipse(in: CGRect(x: -2, y: -2, width: 4, height: 4))
        if random.next() < 0.3 {
            let x = r * 0.33, y = r * 0.2
            ctx.setFillColor(color(0xD2DED0, 0.56).cgColor); ctx.fillEllipse(in: CGRect(x: x, y: y, width: 3.4, height: 2.4))
        }
    }
    static func lotusFlower(_ ctx: CGContext, radius r: Double, random: inout SeededRandom) {
        ctx.setFillColor(color(0x233828, 0.25).cgColor); ctx.fillEllipse(in: CGRect(x: -r + 5, y: -r - 5, width: r * 2, height: r * 2))
        for ring in 0..<3 {
            let count = ring == 2 ? 7 : 11, length = r * (1 - Double(ring) * 0.22)
            for i in 0..<count {
                ctx.saveGState(); ctx.rotate(by: Double(i) / Double(count) * tau + Double(ring) * 0.26)
                let petal = path { p in p.move(to: CGPoint(x: 0, y: -2)); p.addCurve(to: CGPoint(x: 0, y: length), control1: CGPoint(x: -length * 0.55, y: length * 0.28), control2: CGPoint(x: -length * 0.16, y: length * 0.78)); p.addCurve(to: CGPoint(x: 0, y: -2), control1: CGPoint(x: length * 0.16, y: length * 0.78), control2: CGPoint(x: length * 0.55, y: length * 0.28)); p.closeSubpath() }
                fill(ctx, petal, ring == 0 ? 0xC88C92 : ring == 1 ? 0xDFAAB0 : 0xF0D6CE)
                line(ctx, petal, 0xAC777E, width: 0.5, alpha: 0.65)
                line(ctx, path { p in p.move(to: .zero); p.addLine(to: CGPoint(x: 0, y: length * 0.85)) }, 0xFFF0DE, width: 0.4, alpha: 0.6)
                ctx.restoreGState()
            }
        }
        ctx.setFillColor(color(0xD5AE51).cgColor); ctx.fillEllipse(in: CGRect(x: -4, y: -4, width: 8, height: 8))
        for i in 0..<12 { let a = Double(i) / 12 * tau; ctx.setFillColor(color(0xEACA6E).cgColor); ctx.fillEllipse(in: CGRect(x: cos(a) * 5 - 0.7, y: sin(a) * 5 - 0.7, width: 1.4, height: 1.4)) }
    }
    static func seedPod(_ ctx: CGContext) {
        ctx.setFillColor(color(0x8B9A55).cgColor); ctx.fillEllipse(in: CGRect(x: -10, y: -8, width: 20, height: 16))
        for row in -1...1 { for column in -1...1 { ctx.setFillColor(color(0x4B5D36).cgColor); ctx.fillEllipse(in: CGRect(x: Double(column) * 5 - 1.2, y: Double(row) * 4 - 1.2, width: 2.4, height: 2.4)) } }
    }
}
