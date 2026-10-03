import AppKit

struct PondArtwork {
    let bed: CGImage
    let vegetation: [PlantPlacement]
}

struct VegetationCluster {
    let center: CGPoint
    let spread: Double
    let leafCount: Int
    let interior: Bool
}

// The bed is a background plate; plants retain their own full-resolution botanical textures.
enum PondEnvironment {
    static func clusters(size: CGSize) -> [VegetationCluster] {
        let unit = plantUnit(size: size)
        let specs: [(Double, Double, Double, Int, Bool)] = [
            (0.075, 0.16, 170, 8, false),
            (0.91, 0.85, 175, 9, false),
            (0.94, 0.08, 145, 6, false),
            (0.025, 0.67, 145, 6, false),
            (0.57, 0.96, 115, 4, false),
            (0.29, 0.66, 102, 4, true),
            (0.51, 0.23, 105, 4, true),
            (0.73, 0.51, 110, 5, true)
        ]
        return specs.map { x, y, spread, leaves, interior in
            VegetationCluster(center: CGPoint(x: size.width * x, y: size.height * y), spread: spread * unit, leafCount: leaves, interior: interior)
        }
    }

    static func plantUnit(size: CGSize) -> Double { clamp(min(size.width, size.height) / 1150, 0.7, 1.65) }

    static func placements(size: CGSize, density: Double) -> [PlantPlacement] {
        let unit = plantUnit(size: size)
        var result: [PlantPlacement] = []
        for (index, cluster) in clusters(size: size).enumerated() {
            // Each colony has an independent seed; changing density preserves its existing plants.
            var rng = SeededRandom(state: UInt64(395177 + index * 104729))
            for i in 0..<Int((cluster.interior ? 5 : 9) * density) {
                let a = rng.range(0, tau), d = rng.range(15, cluster.spread * 1.05)
                let at = CGPoint(x: cluster.center.x + cos(a) * d, y: cluster.center.y + sin(a) * d * 0.8)
                result.append(PlantPlacement(kind: i % 3 == 0 ? .pondweed : .reed, variant: i % 4, position: at, scale: rng.range(0.65, 1.02) * unit, rotation: rng.range(-2.8, 2.8), submerged: true, order: CGFloat(i) * 0.01))
            }
            // Reset the stream so surface plants are stable when submerged density changes.
            rng = SeededRandom(state: UInt64(582391 + index * 7919))
            for i in 0..<max(2, Int(Double(cluster.leafCount) * density)) {
                let a = rng.range(0, tau), d = sqrt(rng.next()) * cluster.spread
                let at = CGPoint(x: cluster.center.x + cos(a) * d, y: cluster.center.y + sin(a) * d * 0.78)
                let scale = rng.range(0.70, 1.08) * unit * (i % 5 == 3 ? 0.72 : 1)
                result.append(PlantPlacement(kind: (i + index) % 3 == 0 ? .lotus : .lily, variant: (i + index) % 4, position: at, scale: scale, rotation: rng.range(0, tau), submerged: false, order: CGFloat(i) * 0.01))
            }
            // Flowers sit in openings above the leaves, instead of being hidden by later leaves.
            rng = SeededRandom(state: UInt64(85711 + index * 3571))
            let flowers = cluster.interior ? (index == 6 ? 1 : 0) : (index == 1 ? 2 : 1)
            for i in 0..<flowers {
                let at = CGPoint(x: cluster.center.x + rng.range(-0.48, 0.48) * cluster.spread, y: cluster.center.y + rng.range(-0.4, 0.4) * cluster.spread)
                result.append(PlantPlacement(kind: .flower, variant: (index + i) % 4, position: at, scale: rng.range(0.68, 0.85) * unit, rotation: rng.range(0, tau), submerged: false, order: 2))
            }
            for i in 0..<max(1, Int((cluster.interior ? 2 : 4) * density)) {
                let a = rng.range(0, tau), d = rng.range(cluster.spread * 0.85, cluster.spread * 1.45)
                let at = CGPoint(x: cluster.center.x + cos(a) * d, y: cluster.center.y + sin(a) * d * 0.8)
                result.append(PlantPlacement(kind: .duckweed, variant: i % 4, position: at, scale: rng.range(0.75, 1.05) * unit, rotation: rng.range(0, tau), submerged: false, order: 1))
            }
        }
        return result
    }

    static func make(size: CGSize, density: Double, palette: Palette, daylight: Daylight = .noon, rasterScale: CGFloat) -> PondArtwork {
        let scale = min(rasterScale, 4096 / max(size.width, size.height))
        let bounds = CGRect(origin: .zero, size: size)
        let bed = bitmap(bounds: bounds, scale: scale) { ctx in
            ctx.setFillColor(color(palette.water).cgColor); ctx.fill(bounds)
            var rng = SeededRandom(state: 182954)
            for _ in 0..<210 {
                let center = CGPoint(x: rng.range(0, size.width), y: rng.range(0, size.height)), r = rng.range(16, 125)
                fill(ctx, organic(center: center, radius: r, random: &rng), rng.next() < 0.5 ? palette.silt : daylight.apply(0x273F30), alpha: rng.range(0.025, 0.065))
            }
            let grains = min(75000, Int(size.width * size.height / 42))
            for _ in 0..<grains {
                let r = rng.range(0.25, 1.05)
                ctx.setFillColor(color(daylight.apply(rng.next() < 0.58 ? 0xBDBDA1 : 0x213F31), rng.range(0.04, 0.15)).cgColor)
                ctx.fill(CGRect(x: rng.range(0, size.width), y: rng.range(0, size.height), width: r, height: r * 0.7))
            }
            for _ in 0..<480 {
                let center = CGPoint(x: rng.range(0, size.width), y: rng.range(0, size.height))
                pebble(ctx, at: center, radius: rng.range(1.2, 7), random: &rng, daylight: daylight, alpha: 0.32)
            }
            for cluster in clusters(size: size) {
                for _ in 0..<Int((cluster.interior ? 13 : 27) * density) {
                    let a = rng.range(0, tau), d = rng.range(0, cluster.spread * 1.1)
                    pebble(ctx, at: CGPoint(x: cluster.center.x + cos(a) * d, y: cluster.center.y + sin(a) * d * 0.72), radius: rng.range(4, 14) * plantUnit(size: size), random: &rng, daylight: daylight, alpha: 0.44)
                }
            }
            for _ in 0..<26 {
                let x = rng.range(0, size.width), y = rng.range(0, size.height), w = rng.range(55, 180)
                line(ctx, path { p in p.move(to: CGPoint(x: x, y: y)); p.addCurve(to: CGPoint(x: x + w, y: y + 18), control1: CGPoint(x: x + w * 0.3, y: y + 35), control2: CGPoint(x: x + w * 0.55, y: y - 35)) }, daylight.apply(0xD3D8AB), width: 0.8, alpha: 0.07)
            }
        }
        return PondArtwork(bed: bed, vegetation: placements(size: size, density: density))
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
    static func pebble(_ ctx: CGContext, at center: CGPoint, radius: Double, random: inout SeededRandom, daylight: Daylight = .noon, alpha: Double) {
        let p = organic(center: center, radius: radius, random: &random, count: 9)
        ctx.saveGState(); ctx.translateBy(x: 2, y: -2); fill(ctx, p, daylight.apply(0x183D32), alpha: alpha * 0.6); ctx.restoreGState()
        let shades: [UInt32] = [0x849181, 0x6D8171, 0xA5A28A, 0x5E7469, 0x8C8B72].map { daylight.apply($0) }
        fill(ctx, p, shades[Int(random.range(0, 4.99))], alpha: alpha)
        line(ctx, path { p in p.move(to: CGPoint(x: center.x - radius * 0.5, y: center.y + radius * 0.36)); p.addQuadCurve(to: CGPoint(x: center.x + radius * 0.45, y: center.y + radius * 0.36), control: CGPoint(x: center.x, y: center.y + radius * 0.68)) }, daylight.apply(0xD8CFAB), width: max(0.45, radius / 12), alpha: alpha * 0.4)
    }
}
