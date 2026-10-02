import AppKit
import SpriteKit

// 浮叶围绕茎轻漂，浮萍较自由；沉水草保留根部，只弯动叶梢。
final class PlantMotion {
    let sprite: SKSpriteNode
    let placement: PlantPlacement
    private let phase: Double
    private static let grassVertices: [SIMD2<Float>] = [0, 0.125, 0.4167, 0.7083, 1].flatMap { y in
        [SIMD2<Float>(0, Float(y)), SIMD2<Float>(1, Float(y))]
    }
    private static let grassGrid = SKWarpGeometryGrid(columns: 1, rows: 4,
                                                     sourcePositions: grassVertices, destinationPositions: grassVertices)

    init(sprite: SKSpriteNode, placement: PlantPlacement) {
        self.sprite = sprite; self.placement = placement
        phase = (placement.position.x * 0.037 + placement.position.y * 0.023 + Double(placement.variant) * 1.7)
            .truncatingRemainder(dividingBy: tau)
        if placement.submerged { sprite.subdivisionLevels = 1 }
    }

    func animate(time: Double, distance: Double, reducedMotion: Bool, ripple: CGPoint = .zero) {
        guard !reducedMotion else {
            sprite.position = placement.position; sprite.zRotation = placement.rotation
            sprite.warpGeometry = nil; return
        }
        let shared = time * 0.34 + placement.position.x / (720 * distance) + placement.position.y / (580 * distance)
        let local = time * 0.47 + phase
        if placement.submerged {
            // 源网格的第二行正好在茎根，根以下的顶点不移动。
            let bend = sin(shared) * 0.036 + sin(local * 0.83) * 0.018
            let vertices = Self.grassVertices.map { point -> SIMD2<Float> in
                let height = max(0, (Double(point.y) - 0.125) / 0.875)
                let flex = height * height
                let flutter = sin(local + height * 2.1) * 0.008 * flex
                return SIMD2(point.x + Float(bend * flex + flutter), point.y)
            }
            sprite.warpGeometry = Self.grassGrid.replacingByDestinationPositions(positions: vertices)
            sprite.position = placement.position; sprite.zRotation = placement.rotation
            return
        }
        let drift: Double, turn: Double
        switch placement.kind {
        case .duckweed: drift = 9; turn = 0.055
        case .flower: drift = 3; turn = 0.012
        default: drift = 5.5; turn = 0.028
        }
        let dx = sin(shared) * drift * 0.7 + sin(local * 0.61) * drift * 0.3
        let dy = cos(shared * 0.81 + 0.5) * drift * 0.42 + sin(local) * drift * 0.18
        sprite.position = CGPoint(x: placement.position.x + dx * distance + ripple.x,
                                  y: placement.position.y + dy * distance + ripple.y)
        sprite.zRotation = placement.rotation + (sin(shared * 0.76) * 0.65 + sin(local * 0.87) * 0.35) * turn
    }
}
