import AppKit
import SpriteKit
import SwiftUI
import Combine

let appVersion = "1.4.0"
let tau = Double.pi * 2
func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(hi, max(lo, v)) }
func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: alpha)
}
func path(_ draw: (CGMutablePath) -> Void) -> CGPath { let p = CGMutablePath(); draw(p); return p }
func shape(_ p: CGPath, _ fill: NSColor, stroke: NSColor = .clear, width: CGFloat = 1) -> SKShapeNode {
    let n = SKShapeNode(path: p); n.fillColor = fill; n.strokeColor = stroke; n.lineWidth = width; n.isAntialiased = true; return n
}
func ellipse(_ rect: CGRect, _ fill: NSColor, stroke: NSColor = .clear, width: CGFloat = 1) -> SKShapeNode {
    shape(CGPath(ellipseIn: rect, transform: nil), fill, stroke: stroke, width: width)
}

final class Preferences: ObservableObject {
    @Published var count: Double { didSet { save() } }
    @Published var speed: Double { didSet { save() } }
    @Published var theme: String { didSet { save() } }
    @Published var enabled: Bool { didSet { save() } }
    @Published var paused = false { didSet { onChange?() } }
    @Published var lowPower: Bool { didSet { save() } }
    @Published var distance: Double { didSet { save() } }
    @Published var vegetation: Double { didSet { save() } }
    @Published var harmony: Bool { didSet { save() } }
    @Published var interact: Bool { didSet { save() } }
    @Published var feedModifier: String { didSet { save() } }
    @Published var daylightMode: String { didSet { save() } }
    @Published var designs: [FishDesign] { didSet { designData = nil; save() } }
    var onChange: (() -> Void)?
    let defaults: UserDefaults
    // 60 尾鱼的笔画数据可能很大；只有 designs 本身变化才重新编码，
    // 其余设置项保存时直接复用上次的 JSON。
    private var designData: Data?
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let d = defaults
        count = d.object(forKey: "fishCount") == nil ? 24 : clamp(d.double(forKey: "fishCount"), 6, 60)
        speed = d.object(forKey: "swimSpeed") == nil ? 0.8 : clamp(d.double(forKey: "swimSpeed"), 0.3, 1.8)
        theme = d.string(forKey: "waterTheme") ?? "jade"
        enabled = d.object(forKey: "desktopEnabled") == nil ? true : d.bool(forKey: "desktopEnabled")
        lowPower = d.bool(forKey: "lowPower")
        distance = d.object(forKey: "viewDistance") == nil ? 1.65 : clamp(d.double(forKey: "viewDistance"), 1, 2.4)
        vegetation = d.object(forKey: "plantDensity") == nil ? 1.15 : clamp(d.double(forKey: "plantDensity"), 0.5, 1.8)
        harmony = d.object(forKey: "menuBarHarmony") == nil ? true : d.bool(forKey: "menuBarHarmony")
        interact = d.object(forKey: "mouseInteraction") == nil ? true : d.bool(forKey: "mouseInteraction")
        feedModifier = d.string(forKey: "feedModifier") ?? "option"
        let savedDaylight = d.string(forKey: "daylightMode") ?? "auto"
        daylightMode = savedDaylight == "auto" || Daylight.all[savedDaylight] != nil ? savedDaylight : "auto"
        var loaded = (0..<60).map { FishDesign.initial($0) }
        if let data = d.data(forKey: "fishDesigns"), let saved = try? JSONDecoder().decode([FishDesign].self, from: data) {
            for fish in saved where fish.id >= 0 && fish.id < 60 { loaded[fish.id] = fish.validated }
        }
        designs = loaded
    }
    func save() {
        let d = defaults
        d.set(count, forKey: "fishCount"); d.set(speed, forKey: "swimSpeed")
        d.set(theme, forKey: "waterTheme"); d.set(enabled, forKey: "desktopEnabled")
        d.set(lowPower, forKey: "lowPower")
        d.set(distance, forKey: "viewDistance"); d.set(vegetation, forKey: "plantDensity")
        d.set(harmony, forKey: "menuBarHarmony"); d.set(interact, forKey: "mouseInteraction")
        d.set(feedModifier, forKey: "feedModifier")
        d.set(daylightMode, forKey: "daylightMode")
        if designData == nil { designData = try? JSONEncoder().encode(designs) }
        if let data = designData { d.set(data, forKey: "fishDesigns") }
        onChange?()
    }
}

struct Swimmer {
    var x: Double, y: Double, angle: Double, cruise: Double, phase: Double, length: Double
    var turn: Double = 0
    var startledUntil = 0.0, startledFrom = CGPoint.zero
    var meal = CGPoint.zero, hasMeal = false
    mutating func step(dt: Double, time: Double, width: Double, height: Double, speed: Double, targets: [CGPoint], positions: [CGPoint], index: Int, cursor: CGPoint? = nil, curious: Bool = false, cursorRadius: Double = 0) {
        var desired = angle + sin(time * 0.37 + phase) * 0.45 + sin(time * 0.17 + phase * 3) * 0.22
        let margin = min(150.0, min(width, height) * 0.2)
        var fx = cos(desired), fy = sin(desired)
        if x < margin { fx += (margin - x) / margin * 3.5 }
        if x > width - margin { fx -= (x - width + margin) / margin * 3.5 }
        if y < margin { fy += (margin - y) / margin * 3.5 }
        if y > height - margin { fy -= (y - height + margin) / margin * 3.5 }
        for (j, p) in positions.enumerated() where j != index {
            let dx = x - p.x, dy = y - p.y, d2 = dx * dx + dy * dy
            if d2 > 1 && d2 < 85 * 85 { let d = sqrt(d2); fx += dx / d * (1 - d / 85) * 0.7; fy += dy / d * (1 - d / 85) * 0.7 }
        }
        if startledUntil > time {
            let dx = x - startledFrom.x, dy = y - startledFrom.y, d = max(1, hypot(dx, dy))
            fx += dx / d * 3.2; fy += dy / d * 3.2
        } else if curious, let c = cursor {
            // 光标像一根手指：游近了就停在旁边端详，不再贴上去。
            let dx = c.x - x, dy = c.y - y, distance = hypot(dx, dy)
            if distance > 70 && distance < cursorRadius { fx += dx / distance * 0.8; fy += dy / distance * 0.8 }
        }
        // 食物：每尾认准离自己最近的一处，半途不轻易换食（除非另一处近了 25% 以上）；
        // 离得越远冲得越猛，收近了贴进饲料群里啄食。
        var dashing = false
        var nearestDistance = Double.infinity
        if !targets.isEmpty {
            var nearest = targets[0]
            for spot in targets {
                let d = hypot(spot.x - x, spot.y - y)
                if d < nearestDistance { nearestDistance = d; nearest = spot }
            }
            if hasMeal {
                for spot in targets where hypot(spot.x - meal.x, spot.y - meal.y) < 1 {
                    let d = hypot(spot.x - x, spot.y - y)
                    if d < nearestDistance * 1.25 { nearest = spot; nearestDistance = d }
                    break
                }
            }
            meal = nearest; hasMeal = true
            if nearestDistance > 16 {
                let urgency = nearestDistance > 110 ? 4.5 : 3.2
                let dx = nearest.x - x, dy = nearest.y - y
                fx += dx / nearestDistance * urgency; fy += dy / nearestDistance * urgency
                dashing = nearestDistance > 60
            }
        } else { hasMeal = false }
        desired = atan2(fy, fx)
        let delta = atan2(sin(desired - angle), cos(desired - angle))
        // 受惊时急转急游，抢食时利落转向，平时平缓。
        let panicking = startledUntil > time
        let gain = panicking ? 3.4 : dashing ? 3.0 : 1.9
        let turnLimit = panicking ? 2.2 : dashing ? 2.0 : 1.05
        turn += (clamp(delta * gain, -turnLimit, turnLimit) - turn) * min(1, dt * (panicking ? 6 : dashing ? 5.5 : 3))
        angle += turn * dt
        // 受惊先猛地弹开，1.4 秒内收势；抢食冲刺随距离收速。
        var boost = 1.0
        if panicking {
            let left = clamp((startledUntil - time) / 1.4, 0, 1)
            boost = 1 + 6 * left * left
        } else if dashing {
            boost = 1 + 2.2 * clamp((nearestDistance - 60) / 180, 0, 1)
        }
        let velocity = cruise * speed * boost * (1 + 0.12 * sin(time * 1.1 + phase))
        x = clamp(x + cos(angle) * velocity * dt, 28, max(28, width - 28))
        y = clamp(y + sin(angle) * velocity * dt, 28, max(28, height - 28))
    }
}


struct Palette {
    let water: UInt32, silt: UInt32, pebble: UInt32, leaf: UInt32
    init(theme: String, daylight: Daylight = .noon) {
        let base: (water: UInt32, silt: UInt32, pebble: UInt32, leaf: UInt32)
        switch theme {
        case "ink": base = (0x173D40, 0x28504C, 0x59716A, 0x506E45)
        case "blue": base = (0x3B727C, 0x4D8184, 0x82998B, 0x527F53)
        default: base = (0x385E50, 0x737F59, 0x7D9280, 0x557340)
        }
        // 时段光色直接烘进调色板：中午恒等，其余时段整体压暗并推向时段色。
        water = daylight.apply(base.water); silt = daylight.apply(base.silt)
        pebble = daylight.apply(base.pebble); leaf = daylight.apply(base.leaf)
    }
}
struct SeededRandom {
    var state: UInt64 = 84721
    mutating func next() -> Double { state = 2862933555777941757 &* state &+ 3037000493; return Double(state >> 11) / Double(UInt64.max >> 11) }
    mutating func range(_ lo: Double, _ hi: Double) -> Double { lo + next() * (hi - lo) }
}

final class PondScene: SKScene {
    let preferences: Preferences
    var swimmers: [Swimmer] = [], fishNodes: [FishNode] = []
    let floor = SKNode(), inhabitants = SKNode(), surface = SKNode(), plants = SKNode(), foodLayer = SKNode()
    let pondCamera = SKCameraNode()
    var worldSize: CGSize { CGSize(width: size.width * preferences.distance, height: size.height * preferences.distance) }
    var configuredSize = CGSize.zero
    var floorStamp = ""
    var waterStamp = ""
    var daylight = Daylight.noon
    var daylightOverride: Daylight?
    var bedSprite: SKSpriteNode?
    var plantMotions: [PlantMotion] = []
    let water = PondWater()
    var lastTime: TimeInterval = 0, simulationTime: Double = 0
    var wakeClock = 0.0, wakeIndex = 0
    struct FoodSpot { var position: CGPoint, expiry: Double }
    var foodSpots: [FoodSpot] = []
    var allowsFeeding = false
    var cursor: CursorProbe?
    var rng = SeededRandom()
    init(size: CGSize, preferences: Preferences) {
        self.preferences = preferences
        super.init(size: size)
        scaleMode = .resizeFill
        addChild(floor); addChild(inhabitants); addChild(surface); addChild(foodLayer); addChild(pondCamera); camera = pondCamera
        floor.zPosition = -10; inhabitants.zPosition = 0; surface.zPosition = 10; foodLayer.zPosition = 12
        configure()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure() {
        // The desktop has its own cached backing image; a recovering SpriteKit
        // drawable must never cover it with a solid green clear colour.
        let daylight = daylightOverride ?? Daylight.effective(mode: preferences.daylightMode)
        self.daylight = daylight
        backgroundColor = view?.allowsTransparency == true ? .clear : color(Palette(theme: preferences.theme, daylight: daylight).water)
        let world = worldSize
        guard world.width > 56, world.height > 56 else { return }
        let rasterScale = (view?.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2) / preferences.distance
        if configuredSize != world {
            if configuredSize.width > 0 && configuredSize.height > 0 {
                for i in swimmers.indices { swimmers[i].x *= world.width / configuredSize.width; swimmers[i].y *= world.height / configuredSize.height }
                for i in foodSpots.indices {
                    foodSpots[i].position = CGPoint(x: foodSpots[i].position.x * world.width / configuredSize.width, y: foodSpots[i].position.y * world.height / configuredSize.height)
                }
            }
            pondCamera.position = CGPoint(x: world.width / 2, y: world.height / 2); pondCamera.setScale(preferences.distance)
            configuredSize = world
        }
        // Slider drags re-bake only when a bucket (density 0.1, distance 0.125) changes; the bed
        // plate itself is proportional, so between buckets it is simply stretched for free.
        let stamp = "\(preferences.theme)|\(daylight.key)|\(Int((preferences.vegetation * 10).rounded()))|\(Int(size.width))x\(Int(size.height))|\(Int((preferences.distance * 8).rounded()))|\(String(format: "%.2f", rasterScale))"
        if stamp != floorStamp { floorStamp = stamp; buildFloor(rasterScale: rasterScale) }
        bedSprite?.size = worldSize
        bedSprite?.position = CGPoint(x: worldSize.width / 2, y: worldSize.height / 2)
        if let bed = bedSprite {
            // 任意设置变更都会走 configure：水面只在屏幕、视野、池底纹理或“减少动态效果”
            // 变化时重建，暂停、滑块等不再清掉进行中的涟漪和反光。
            let reducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            let stamp = "\(Int(size.width))x\(Int(size.height))|\(preferences.distance)|\(reducedMotion)|\(daylight.key)|\(ObjectIdentifier(bed).hashValue)"
            if stamp != waterStamp {
                waterStamp = stamp
                water.configure(size: worldSize, distance: preferences.distance, bed: bed, floor: floor, surface: surface, reducedMotion: reducedMotion, daylight: daylight)
            }
        }
        animatePlants()
        let count = Int(preferences.count.rounded())
        while swimmers.count > count { swimmers.removeLast(); fishNodes.removeLast().removeFromParent() }
        while swimmers.count < count {
            let i = swimmers.count, length = rng.range(74, 123)
            let swimmer = Swimmer(x: rng.range(80, max(81, world.width - 80)), y: rng.range(80, max(81, world.height - 80)), angle: rng.range(0, tau), cruise: rng.range(24, 48), phase: rng.range(0, tau), length: length)
            let fish = FishNode(index: i, design: preferences.designs[i], size: length)
            fish.zPosition = CGFloat(i % 3); inhabitants.addChild(fish); swimmers.append(swimmer); fishNodes.append(fish)
        }
        for i in swimmers.indices {
            let design = preferences.designs[i]
            if fishNodes[i].designKey != design.artworkKey {
                fishNodes[i].removeFromParent()
                let replacement = FishNode(index: i, design: design, size: swimmers[i].length)
                replacement.zPosition = CGFloat(i % 3); inhabitants.addChild(replacement); fishNodes[i] = replacement
            }
            fishNodes[i].setScale(swimmers[i].length / 115 * design.size)
            fishNodes[i].applyDaylight(daylight.tint, blend: daylight.fishBlend)
            fishNodes[i].animate(time: simulationTime, swimmer: swimmers[i], speed: preferences.speed)
        }
        view?.preferredFramesPerSecond = preferences.lowPower ? 20 : 30
        isPaused = preferences.paused; lastTime = 0
    }
    override func didMove(to view: SKView) { configure() }
    override func didChangeSize(_ oldSize: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        configure()
    }
    func buildFloor(rasterScale: CGFloat) {
        floor.removeAllChildren(); plants.removeAllChildren(); plantMotions.removeAll()
        if plants.parent == nil { surface.addChild(plants) }
        let palette = Palette(theme: preferences.theme, daylight: daylight)
        let artwork = PondEnvironment.make(size: worldSize, density: preferences.vegetation, palette: palette, daylight: daylight, rasterScale: rasterScale)
        let bed = SKSpriteNode(texture: SKTexture(cgImage: artwork.bed), size: worldSize)
        bed.position = CGPoint(x: worldSize.width / 2, y: worldSize.height / 2); bed.zPosition = -1; floor.addChild(bed)
        bedSprite = bed
        for placement in artwork.vegetation {
            let sprite = PlantPainter.sprite(placement)
            if placement.submerged {
                sprite.alpha = 0.64; sprite.color = color(palette.water); sprite.colorBlendFactor = 0.18
            } else if daylight.plantBlend > 0 {
                sprite.color = color(daylight.tint); sprite.colorBlendFactor = daylight.plantBlend
            }
            (placement.submerged ? floor : plants).addChild(sprite)
            plantMotions.append(PlantMotion(sprite: sprite, placement: placement))
        }
    }
    func animatePlants() {
        for motion in plantMotions {
            motion.animate(time: simulationTime, distance: preferences.distance, reducedMotion: water.reducedMotion,
                           ripple: water.displacement(at: motion.placement.position, time: simulationTime))
        }
    }
    // 视图/屏幕坐标 → 池塘世界坐标（相机拉近拉远时同样成立）。
    func worldPoint(fromView v: CGPoint) -> CGPoint {
        CGPoint(x: (v.x - size.width / 2) * pondCamera.xScale + pondCamera.position.x,
                y: (v.y - size.height / 2) * pondCamera.yScale + pondCamera.position.y)
    }
    func worldPoint(fromScreen p: NSPoint) -> CGPoint? {
        guard let window = view?.window else { return nil }
        let local = window.convertFromScreen(NSRect(origin: p, size: .zero)).origin
        return worldPoint(fromView: local)
    }
    // 急挥的光标惊散附近鱼群：一小段时间内全力逃离该点。
    func startle(near point: CGPoint) {
        let radius = min(worldSize.width, worldSize.height) * 0.28
        for i in swimmers.indices where hypot(swimmers[i].x - point.x, swimmers[i].y - point.y) < radius {
            swimmers[i].startledUntil = simulationTime + 1.4; swimmers[i].startledFrom = point
        }
    }
    func feed(at point: CGPoint? = nil) {
        // 多处投喂并存：新饲料不清除旧饲料，鱼群各自扑向最近一处；最多保留 5 处，再投替换最早的。
        let center = point ?? CGPoint(x: rng.range(worldSize.width * 0.25, worldSize.width * 0.75), y: rng.range(worldSize.height * 0.25, worldSize.height * 0.75))
        foodSpots.append(FoodSpot(position: center, expiry: simulationTime + 16))
        if foodSpots.count > 5 { foodSpots.removeFirst() }
        for _ in 0..<16 {
            let crumb = ellipse(CGRect(x: -2, y: -2, width: 4, height: 4), color(0xE7CAA0), stroke: color(0x94724B), width: 0.5)
            crumb.position = CGPoint(x: center.x + rng.range(-24, 24), y: center.y + rng.range(-24, 24)); foodLayer.addChild(crumb)
            crumb.run(.sequence([.wait(forDuration: rng.range(7, 14)), .fadeOut(withDuration: 2), .removeFromParent()]))
        }
        addRipple(at: center)
    }
    func addRipple(at point: CGPoint) {
        water.addRipple(at: point, time: simulationTime)
    }
    override func mouseDown(with event: NSEvent) {
        guard allowsFeeding, let view else { return }
        // location(in: SKNode) 已应用相机；从视图取点，再换算一次世界坐标。
        feed(at: worldPoint(fromView: view.convert(event.locationInWindow, from: nil)))
    }
    override func update(_ currentTime: TimeInterval) {
        guard !preferences.paused, worldSize.width > 56, worldSize.height > 56 else { lastTime = 0; return }
        let dt = lastTime == 0 ? 0 : min(0.05, currentTime - lastTime)
        lastTime = currentTime; simulationTime += dt
        water.update(time: simulationTime)
        animatePlants()
        foodSpots.removeAll { simulationTime > $0.expiry }
        // 光标互动：6 秒内的光标还算“在场”；静止或缓动的光标让附近金鱼好奇，急挥则已被上层惊散。
        var cursorPoint: CGPoint? = nil, curious = false
        if preferences.interact, let probe = cursor {
            let age = -probe.updated.timeIntervalSinceNow
            if age < 6 {
                cursorPoint = probe.world
                curious = probe.speed < CursorStream.calmSpeed || age > 0.3
            }
        }
        let cursorRadius = min(worldSize.width, worldSize.height) * 0.35
        let targets = foodSpots.map { $0.position }
        let positions = swimmers.map { CGPoint(x: $0.x, y: $0.y) }
        for i in swimmers.indices {
            swimmers[i].step(dt: dt, time: simulationTime, width: worldSize.width, height: worldSize.height, speed: preferences.speed, targets: targets, positions: positions, index: i, cursor: cursorPoint, curious: curious, cursorRadius: cursorRadius)
            fishNodes[i].animate(time: simulationTime, swimmer: swimmers[i], speed: preferences.speed)
        }
        // 浅水中的鱼偶尔带动水面，保持稀疏尾波，避免每条鱼都画出一圈圈靶心。
        wakeClock += dt
        if !water.reducedMotion, wakeClock > 2.4, !swimmers.isEmpty {
            wakeClock = 0; wakeIndex = (wakeIndex + 7) % swimmers.count
            let fish = swimmers[wakeIndex]
            let point = CGPoint(x: fish.x - cos(fish.angle) * fish.length * 0.4,
                                y: fish.y - sin(fish.angle) * fish.length * 0.4)
            water.addRipple(at: point, time: simulationTime, strength: 0.16, radius: 72)
        }
    }
}

final class DesktopWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
final class PreviewWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

struct PondCanvas: NSViewRepresentable {
    let scene: PondScene
    func makeNSView(context: Context) -> SKView {
        let view = SKView(frame: CGRect(origin: .zero, size: scene.size)); view.preferredFramesPerSecond = scene.preferences.lowPower ? 20 : 30
        view.ignoresSiblingOrder = true; view.presentScene(scene)
        return view
    }
    func updateNSView(_ nsView: SKView, context: Context) { }
}

struct SettingsView: View {
    @ObservedObject var preferences: Preferences
    var compact = false
    var feed: () -> Void
    var preview: () -> Void
    var quit: () -> Void
    var edit: () -> Void = {}
    let ink = Color(nsColor: color(0xEDEAD8)), muted = Color(nsColor: color(0xA5B7AA))
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("一池").font(.custom("STSongti-SC-Regular", size: compact ? 30 : 36))
                        Text("让桌面，慢下来。").font(.system(size: 11)).foregroundStyle(muted)
                    }
                    Spacer()
                    Image(systemName: "water.waves").font(.system(size: 23, weight: .light)).foregroundStyle(Color(nsColor: color(0xBECA9C)))
                }.padding(.bottom, 5)
                HStack(spacing: 7) {
                    Circle().fill(Color(nsColor: color(0xB5C590))).frame(width: 6, height: 6)
                    Text(preferences.enabled ? (preferences.paused ? "池塘已暂停" : "金鱼正在桌面游动 · \(Daylight.effective(mode: preferences.daylightMode).name)") : "桌面池塘已关闭").font(.system(size: 11)).foregroundStyle(muted)
                }
                divider
                sectionLabel("池塘里的居民")
                VStack(spacing: 6) {
                    HStack { Text("金鱼数量"); Spacer(); Text("\(Int(preferences.count.rounded())) 尾").monospacedDigit() }
                    Slider(value: $preferences.count, in: 6...60, step: 1)
                }
                VStack(spacing: 6) {
                    HStack { Text("游动速度"); Spacer(); Text(preferences.speed < 0.6 ? "悠闲" : preferences.speed < 1.2 ? "自然" : "活泼").foregroundStyle(muted) }
                    Slider(value: $preferences.speed, in: 0.3...1.8)
                }
                Button(action: edit) { Label("金鱼画室 · 颜色与花纹", systemImage: "paintbrush.pointed").frame(maxWidth: .infinity) }.buttonStyle(.bordered).controlSize(.large)
                divider
                sectionLabel("一汪池水")
                HStack(spacing: 10) { themeButton("jade", "青池", 0x385E50); themeButton("ink", "墨池", 0x173D40); themeButton("blue", "晴池", 0x3B727C) }
                VStack(spacing: 6) {
                    HStack { Text("时间光线"); Spacer(); Text(Daylight.effective(mode: preferences.daylightMode).name).foregroundStyle(muted) }
                    Picker("时间光线", selection: $preferences.daylightMode) {
                        ForEach([("auto", "自动"), ("dawn", "凌晨"), ("noon", "中午"), ("dusk", "傍晚"), ("night", "晚上")], id: \.0) { choice in
                            Text(choice.1).tag(choice.0)
                        }
                    }.labelsHidden().pickerStyle(.segmented)
                }
                VStack(spacing: 6) {
                    HStack { Text("视野远近"); Spacer(); Text(String(format: "%.2f ×", preferences.distance)).monospacedDigit().foregroundStyle(muted) }
                    Slider(value: $preferences.distance, in: 1...2.4)
                    HStack { Text("近观"); Spacer(); Text("远眺") }.font(.system(size: 10)).foregroundStyle(muted)
                }
                VStack(spacing: 6) {
                    HStack { Text("植物丰茂度"); Spacer(); Text(preferences.vegetation < 0.8 ? "疏朗" : preferences.vegetation < 1.4 ? "自然" : "丰茂").foregroundStyle(muted) }
                    Slider(value: $preferences.vegetation, in: 0.5...1.8)
                }
                divider
                Toggle("显示在桌面", isOn: $preferences.enabled).toggleStyle(.switch)
                Toggle("鼠标互动 · 涟漪与投喂", isOn: $preferences.interact).toggleStyle(.switch)
                HStack {
                    Text("投喂修饰键").frame(minWidth: 64, alignment: .leading)
                    Spacer()
                    Picker("投喂修饰键", selection: $preferences.feedModifier) {
                        ForEach(feedModifierChoices, id: \.key) { choice in
                            Text(choice.symbol).tag(choice.key)
                        }
                    }.labelsHidden().pickerStyle(.segmented).frame(width: 140)
                }
                Toggle("菜单栏融合 · 池塘壁纸", isOn: $preferences.harmony).toggleStyle(.switch)
                Toggle("节能模式 · 20 帧", isOn: $preferences.lowPower).toggleStyle(.switch)
                Text("桌面图标照常使用，设置自动保存。鼠标缓缓拂过水面泛起涟漪，附近的金鱼会好奇靠近；按住 \(feedModifierName(preferences.feedModifier)) 轻点桌面空白处才投喂，普通点击不触发，快速挥动会惊散鱼群。菜单栏融合会临时使用池塘壁纸，切回桌面时直接显示池塘，关闭或退出时恢复原图。").font(.system(size: 10)).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button(action: feed) { Label("投喂", systemImage: "circle.dotted").frame(maxWidth: .infinity) }
                    Button { preferences.paused.toggle() } label: { Label(preferences.paused ? "继续" : "暂停", systemImage: preferences.paused ? "play" : "pause").frame(maxWidth: .infinity) }
                }.buttonStyle(.bordered).controlSize(.large)
                HStack {
                    if compact { Button("打开池塘预览", action: preview).buttonStyle(.plain) }
                    else { Text("点击水面投喂；桌面需按住 \(feedModifierName(preferences.feedModifier)) 轻点空白处。").foregroundStyle(muted) }
                    Spacer(); Button("退出", action: quit).buttonStyle(.plain).foregroundStyle(muted)
                }.font(.system(size: 11))
            }.font(.system(size: 12)).padding(24)
        }
        .frame(width: compact ? 340 : 300)
        .foregroundStyle(ink).background(Color(nsColor: color(0x203E35)))
        .tint(Color(nsColor: color(0xAFBE8F))).preferredColorScheme(.dark)
    }
    var divider: some View { Rectangle().fill(Color(nsColor: color(0x426054))).frame(height: 1) }
    func sectionLabel(_ text: String) -> some View { Text(text).font(.system(size: 10, weight: .medium)).tracking(2).foregroundStyle(muted) }
    func themeButton(_ key: String, _ title: String, _ hex: UInt32) -> some View {
        Button { preferences.theme = key } label: {
            VStack(spacing: 7) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7).fill(Color(nsColor: color(hex))).frame(height: 31)
                    if preferences.theme == key { Image(systemName: "checkmark").font(.system(size: 12, weight: .semibold)) }
                }.overlay(RoundedRectangle(cornerRadius: 7).stroke(preferences.theme == key ? Color(nsColor: color(0xC2CBA0)) : Color(nsColor: color(0x587367)), lineWidth: 1))
                Text(title).font(.system(size: 11)).foregroundStyle(preferences.theme == key ? ink : muted)
            }.frame(maxWidth: .infinity)
        }.buttonStyle(.plain)
    }
}

struct PreviewContent: View {
    @ObservedObject var preferences: Preferences
    let scene: PondScene
    let feed: () -> Void
    let quit: () -> Void
    let edit: () -> Void
    var body: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                PondCanvas(scene: scene)
                VStack(alignment: .leading, spacing: 6) {
                    Text("片刻涟漪").font(.custom("STSongti-SC-Regular", size: 27))
                    Text("一池金鱼，自在游弋").font(.system(size: 11)).tracking(2)
                }.foregroundStyle(Color(nsColor: color(0xECEDD5))).padding(30).allowsHitTesting(false)
                VStack {
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: "cursorarrow.rays")
                        Text("点击水面投喂")
                        Spacer()
                        Text("YICHI / \(appVersion)").tracking(1.5)
                    }.font(.system(size: 10)).foregroundStyle(Color(nsColor: color(0xD4DDC7))).padding(24).allowsHitTesting(false)
                }.allowsHitTesting(false)
            }.frame(minWidth: 600, minHeight: 570)
            SettingsView(preferences: preferences, feed: feed, preview: {}, quit: quit, edit: edit)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let preferences = Preferences()
    var statusItem: NSStatusItem!
    let popover = NSPopover()
    var desktopWindows: [DesktopWindow] = []
    var desktopScenes: [PondScene] = []
    var previewWindow: NSWindow?, previewScene: PondScene?
    var editorWindow: NSWindow?, editorState: FishEditorState?
    var observers: [NSObjectProtocol] = []
    var rebuilding = false
    var systemSuspended = false
    var settingsWork: DispatchWorkItem?
    var daylightTimer: Timer?
    var rendering = false
    let stream = CursorStream()
    var cursorMonitors: [Any] = []
    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--self-test") { runSelfTests(); return }
        if let index = CommandLine.arguments.firstIndex(of: "--render-preview"), CommandLine.arguments.count > index + 1 {
            rendering = true
            let daylight = CommandLine.arguments.firstIndex(of: "--daylight").flatMap { offset in
                CommandLine.arguments.count > offset + 1 ? Daylight.all[CommandLine.arguments[offset + 1]] : nil
            }
            renderPreview(to: CommandLine.arguments[index + 1], daylight: daylight)
            return
        }
        if let index = CommandLine.arguments.firstIndex(of: "--render-matrix"), CommandLine.arguments.count > index + 1 {
            rendering = true; renderMatrix(to: CommandLine.arguments[index + 1]); return
        }
        NSApp.setActivationPolicy(.accessory)
        installStatusItem()
        installMainMenu()
        installCursorInteraction()
        preferences.onChange = { [weak self] in self?.scheduleSettings() }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.rebuildDesktop() })
        let nc = NSWorkspace.shared.notificationCenter
        observers.append(nc.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refreshDesktop()
        })
        observers.append(nc.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.applySettings()
        })
        for event in [NSWorkspace.screensDidSleepNotification, NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(nc.addObserver(forName: event, object: nil, queue: .main) { [weak self] _ in self?.suspend(true) })
        }
        for event in [NSWorkspace.screensDidWakeNotification, NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(nc.addObserver(forName: event, object: nil, queue: .main) { [weak self] _ in self?.suspend(false) })
        }
        rebuildDesktop()
        // 自动时段按本地时钟在边界切换：每分钟对表一次，唤醒后的刷新在 suspend(false) 里做。
        daylightTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.applySettings() }
        let hasLaunched = UserDefaults.standard.bool(forKey: "hasLaunched")
        if !hasLaunched || CommandLine.arguments.contains("--preview") { showPreview() }
        UserDefaults.standard.set(true, forKey: "hasLaunched")
    }
    func installMainMenu() {
        let main = NSMenu()
        let root = NSMenuItem(); main.addItem(root)
        let menu = NSMenu(); root.submenu = menu
        let preview = NSMenuItem(title: "池塘预览", action: #selector(openPreview), keyEquivalent: "1")
        preview.target = self; menu.addItem(preview)
        let settings = NSMenuItem(title: "池塘设置…", action: #selector(togglePopover(_:)), keyEquivalent: ",")
        settings.target = self; menu.addItem(settings)
        let editor = NSMenuItem(title: "金鱼画室…", action: #selector(showEditor), keyEquivalent: "2")
        editor.target = self; menu.addItem(editor)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出一池", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        NSApp.mainMenu = main
    }
    @objc func openPreview() { showPreview() }
    func installStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "fish", accessibilityDescription: "一池动态桌面") ?? NSImage(systemSymbolName: "water.waves", accessibilityDescription: "一池")
            image?.isTemplate = true; button.image = image; button.toolTip = "一池 · 金鱼动态桌面"
            button.target = self; button.action = #selector(togglePopover(_:)); button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        popover.behavior = .transient
        popover.contentSize = CGSize(width: 340, height: 782)
        popover.contentViewController = NSHostingController(rootView: SettingsView(preferences: preferences, compact: true, feed: { [weak self] in self?.feedAll() }, preview: { [weak self] in self?.popover.close(); self?.showPreview() }, quit: { NSApp.terminate(nil) }, edit: { [weak self] in self?.popover.close(); self?.showEditor() }))
    }
    @objc func togglePopover(_ sender: Any?) {
        if popover.isShown { popover.performClose(sender) }
        else if let button = statusItem.button { popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY); popover.contentViewController?.view.window?.makeKey() }
    }
    func scheduleSettings() {
        settingsWork?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.applySettings() }
        settingsWork = item; DispatchQueue.main.asyncAfter(deadline: .now() + 0.16, execute: item)
    }
    func applySettings() {
        if preferences.enabled && desktopWindows.isEmpty { rebuildDesktop() }
        if !preferences.enabled { closeDesktop() }
        for scene in desktopScenes + (previewScene.map { [$0] } ?? []) { scene.configure(); if systemSuspended { scene.isPaused = true } }
        for window in desktopWindows { (window.contentView as? DesktopPondView)?.updateBackdrop() }
        syncWallpaper()
    }
    func syncWallpaper(onlyManaged: Bool = false) {
        if preferences.enabled && preferences.harmony {
            for window in desktopWindows {
                guard let screen = window.screen, let view = window.contentView as? DesktopPondView,
                      let frame = view.backdrop else { continue }
                WallpaperSync.apply(screen: screen, frame: frame, stamp: view.backdropStamp, defaults: preferences.defaults, onlyManaged: onlyManaged)
            }
        } else {
            WallpaperSync.restore(defaults: preferences.defaults)
        }
    }
    func closeDesktop() {
        for window in desktopWindows { (window.contentView as? DesktopPondView)?.renderer.presentScene(nil); window.close() }
        desktopWindows.removeAll(); desktopScenes.removeAll()
    }
    func rebuildDesktop() {
        guard !rendering, !rebuilding else { return }
        rebuilding = true; defer { rebuilding = false }
        closeDesktop()
        guard preferences.enabled else { syncWallpaper(); return }
        for screen in NSScreen.screens {
            let window = DesktopWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false, screen: screen)
            window.isReleasedWhenClosed = false; window.title = "一池桌面"
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
            window.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            window.ignoresMouseEvents = true; window.hasShadow = false
            window.isOpaque = true; window.backgroundColor = .clear; window.animationBehavior = .none
            let view = DesktopPondView(frame: CGRect(origin: .zero, size: screen.frame.size))
            view.renderer.preferredFramesPerSecond = preferences.lowPower ? 20 : 30
            let scene = PondScene(size: screen.frame.size, preferences: preferences)
            window.contentView = view; view.renderer.presentScene(scene)
            view.updateBackdrop()
            window.setFrame(screen.frame, display: true); window.orderFrontRegardless()
            if systemSuspended { scene.isPaused = true }
            desktopWindows.append(window); desktopScenes.append(scene)
        }
        syncWallpaper()
    }
    func refreshDesktop() {
        syncWallpaper(onlyManaged: true)
        for (window, scene) in zip(desktopWindows, desktopScenes) where window.isOnActiveSpace {
            scene.lastTime = 0
            scene.isPaused = systemSuspended || preferences.paused
            window.contentView?.needsDisplay = true
            window.displayIfNeeded()
        }
    }
    func suspend(_ value: Bool) {
        systemSuspended = value
        for scene in desktopScenes + (previewScene.map { [$0] } ?? []) {
            scene.lastTime = 0; scene.isPaused = value || preferences.paused
        }
        if !value { applySettings() }  // 唤醒后立即对齐时段光色
    }
    func feedAll() {
        if preferences.paused { preferences.paused = false }
        for scene in desktopScenes + (previewScene.map { [$0] } ?? []) { scene.feed() }
    }
    @objc func showEditor() {
        if let window = editorWindow { NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil); return }
        let state = FishEditorState(preferences: preferences)
        let window = PreviewWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "一池 · 金鱼画室"; window.titlebarAppearsTransparent = true
        window.backgroundColor = color(0x1B3028); window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = NSHostingView(rootView: FishEditorContent(preferences: preferences, state: state, done: { [weak self] in self?.editorWindow?.close(); self?.showPreview() }))
        window.minSize = NSSize(width: 970, height: 680); window.isReleasedWhenClosed = false; window.delegate = self
        window.center(); editorState = state; editorWindow = window
        NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)
    }
    func showPreview() {
        if let window = previewWindow { NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil); return }
        let scene = PondScene(size: CGSize(width: 860, height: 760), preferences: preferences); scene.allowsFeeding = true
        let window = PreviewWindow(contentRect: NSRect(x: 0, y: 0, width: 1160, height: 760), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "一池 · 金鱼动态桌面"; window.titlebarAppearsTransparent = true
        window.backgroundColor = color(0x203E35); window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = NSHostingView(rootView: PreviewContent(preferences: preferences, scene: scene, feed: { [weak self] in self?.feedAll() }, quit: { NSApp.terminate(nil) }, edit: { [weak self] in self?.popover.close(); self?.showEditor() }))
        window.minSize = NSSize(width: 920, height: 640); window.isReleasedWhenClosed = false; window.delegate = self
        window.center(); previewScene = scene; previewWindow = window
        NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)
    }
    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window === editorWindow { editorState?.flush(); editorWindow = nil; editorState = nil }
        if let window = notification.object as? NSWindow, window === previewWindow {
            previewScene?.view?.presentScene(nil); previewWindow = nil; previewScene = nil
        }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showPreview(); return true }
    func applicationWillTerminate(_ notification: Notification) {
        editorState?.flush(); closeDesktop()
        if !rendering { WallpaperSync.restore(defaults: preferences.defaults) }
    }
    func renderPreview(to output: String, daylight: Daylight? = nil) {
        NSApp.setActivationPolicy(.accessory)
        let scene = PondScene(size: CGSize(width: 1440, height: 900), preferences: preferences)
        scene.daylightOverride = daylight
        let window = PreviewWindow(contentRect: NSRect(x: 0, y: 0, width: 1440, height: 900), styleMask: .borderless, backing: .buffered, defer: false)
        let view = SKView(frame: window.contentLayoutRect); view.presentScene(scene); window.contentView = view
        previewWindow = window; window.orderFront(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            guard let image = WallpaperSync.snapshotImage(view: view, scene: scene), self.writePNG(image, to: URL(fileURLWithPath: output))
            else { print("无法生成预览"); exit(1) }
            print("预览已保存：\(output)"); NSApp.terminate(nil)
        }
    }
    func writePNG(_ image: CGImage, to url: URL) -> Bool {
        guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return false }
        do { try data.write(to: url, options: .atomic); return true } catch { return false }
    }
    // 3 主题 × 3 视野 × 3 丰茂度的批量截图，附 index.html 拼览页；用隔离偏好，不触碰真实设置与壁纸。
    func renderMatrix(to directory: String) {
        NSApp.setActivationPolicy(.accessory)
        let url = URL(fileURLWithPath: directory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let suite = "studio.yichi.matrix.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let preferences = Preferences(defaults: defaults)
        preferences.daylightMode = "noon"  // 矩阵固定中午光色，便于跨版本对比
        let window = PreviewWindow(contentRect: NSRect(x: 0, y: 0, width: 1440, height: 900), styleMask: .borderless, backing: .buffered, defer: false)
        let view = SKView(frame: window.contentLayoutRect); window.contentView = view
        window.orderFront(nil)
        var rows: [(theme: String, file: String, distance: Double, density: Double)] = []
        for theme in ["jade", "ink", "blue"] {
            for distance in [1.0, 1.65, 2.4] {
                for density in [0.5, 1.15, 1.8] {
                    rows.append((theme, "pond-\(theme)-d\(String(format: "%.2f", distance))-v\(String(format: "%.1f", density)).png", distance, density))
                }
            }
        }
        func step(_ index: Int) {
            guard index < rows.count else {
                try? Self.matrixHTML(rows: rows).write(to: url.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
                defaults.removePersistentDomain(forName: suite)
                print("矩阵已保存：\(url.path)（\(rows.count) 张 + index.html）"); NSApp.terminate(nil)
                return
            }
            let row = rows[index]
            preferences.theme = row.theme; preferences.distance = row.distance; preferences.vegetation = row.density
            let scene = PondScene(size: CGSize(width: 1440, height: 900), preferences: preferences)
            view.presentScene(scene)
            // 首帧包含着色器编译，多等一点；之后各组合 0.7 秒足够游出自然姿态。
            DispatchQueue.main.asyncAfter(deadline: .now() + (index == 0 ? 1.5 : 0.7)) {
                guard let image = WallpaperSync.snapshotImage(view: view, scene: scene), self.writePNG(image, to: url.appendingPathComponent(row.file))
                else { print("无法生成预览"); exit(1) }
                print("已渲染 \(index + 1)/\(rows.count)：\(row.file)")
                step(index + 1)
            }
        }
        step(0)
    }
    static func matrixHTML(rows: [(theme: String, file: String, distance: Double, density: Double)]) -> String {
        let names = ["jade": "青池", "ink": "墨池", "blue": "晴池"]
        var sheets = ""
        for theme in ["jade", "ink", "blue"] {
            sheets += "<h2>\(names[theme] ?? theme)</h2><table>"
            for distance in [1.0, 1.65, 2.4] {
                sheets += "<tr>"
                for density in [0.5, 1.15, 1.8] {
                    let row = rows.first { $0.theme == theme && $0.distance == distance && $0.density == density }!
                    sheets += "<td><img src=\"\(row.file)\" alt=\"\(row.file)\"><div class=\"cap\">\(String(format: "%.2f", distance)) × · 丰茂 \(String(format: "%.1f", density))</div></td>"
                }
                sheets += "</tr>"
            }
            sheets += "</table>"
        }
        return """
        <!DOCTYPE html><html lang="zh"><head><meta charset="utf-8"><title>一池 · 渲染矩阵</title>
        <style>body{background:#152B23;color:#EDEAD8;font:14px -apple-system;margin:28px}
        h1{font-size:19px;font-weight:600}h2{font-size:15px;margin:22px 0 10px;letter-spacing:2px}
        table{border-collapse:collapse}td{padding:6px;text-align:center;font-size:12px;opacity:.85}
        img{width:380px;border-radius:8px;display:block}</style></head><body>
        <h1>一池渲染矩阵 · 3 主题 × 3 视野 × 3 丰茂度</h1>\(sheets)</body></html>
        """
    }
    func runSelfTests() {
        rendering = true
        runWallpaperChecks()
        let suite = "studio.yichi.tests.\(UUID().uuidString)"
        let isolated = UserDefaults(suiteName: suite)!
        defer { isolated.removePersistentDomain(forName: suite) }
        let preferences = Preferences(defaults: isolated)
        preferences.daylightMode = "noon"  // 固定中午光色（恒等），其余时段由 runDaylightChecks 覆盖
        var random = SeededRandom()
        for speed in [0.3, 0.8, 1.8] {
            for dimensions in [(1440.0, 900.0), (800.0, 600.0), (3440.0, 1440.0)] {
                var school = (0..<60).map { _ in Swimmer(x: random.range(28, dimensions.0 - 28), y: random.range(28, dimensions.1 - 28), angle: random.range(0, tau), cruise: random.range(24, 48), phase: random.range(0, tau), length: 100) }
                for frame in 0..<1800 {
                    let points = school.map { CGPoint(x: $0.x, y: $0.y) }
                    for i in school.indices {
                        let target = frame > 900 ? CGPoint(x: dimensions.0 / 2, y: dimensions.1 / 2) : nil
                        school[i].step(dt: 1.0 / 30, time: Double(frame) / 30, width: dimensions.0, height: dimensions.1, speed: speed, targets: target.map { [$0] } ?? [], positions: points, index: i)
                        let fish = school[i]
                        precondition(fish.x.isFinite && fish.y.isFinite && fish.angle.isFinite, "鱼群状态必须为有限数")
                        precondition(fish.x >= 28 && fish.x <= dimensions.0 - 28 && fish.y >= 28 && fish.y <= dimensions.1 - 28, "金鱼不能越过边界")
                        precondition(abs(fish.turn) <= 2.2, "转向不能超过受惊档上限")
                    }
                }
            }
        }
        let scene = PondScene(size: CGSize(width: 1440, height: 900), preferences: preferences)
        precondition(scene.swimmers.count == Int(preferences.count.rounded()))
        scene.update(1); scene.update(2)
        precondition(scene.simulationTime <= 0.05)
        let before = scene.simulationTime; preferences.paused = true; scene.update(3)
        precondition(scene.simulationTime == before)
        preferences.paused = false; scene.update(99); precondition(scene.simulationTime == before)
        scene.feed(at: CGPoint(x: 500, y: 400))
        precondition(scene.foodSpots.last?.position == CGPoint(x: 500, y: 400), "投喂必须落在指定位置")
        scene.feed(at: CGPoint(x: 700, y: 400))
        precondition(scene.foodSpots.count == 2, "多处投喂必须并存，新饲料不能清除旧饲料")
        runDesignChecks(preferences: preferences)
        print("通过：60 尾金鱼 × 3 档速度 × 3 种屏幕尺寸，连续模拟 60 秒；边界、转向、投喂、暂停及恢复均正常。")
        NSApp.terminate(nil)
    }
}
