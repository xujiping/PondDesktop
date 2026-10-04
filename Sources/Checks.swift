import AppKit
import SpriteKit

func runWallpaperChecks() {
    let size = CGSize(width: 320, height: 200)
    let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let view = SKView(frame: CGRect(origin: .zero, size: size))
    window.contentView = view
    let scene = SKScene(size: size)
    scene.backgroundColor = color(0x385E50)
    let marker = SKSpriteNode(color: .red, size: CGSize(width: 40, height: 40))
    marker.position = CGPoint(x: 320, y: 200); scene.addChild(marker)
    let camera = SKCameraNode()
    camera.position = marker.position; camera.setScale(2); scene.addChild(camera); scene.camera = camera
    view.presentScene(scene)
    guard let image = WallpaperSync.snapshotImage(view: view, scene: scene) else { preconditionFailure("尚未显示的桌面窗口也必须能提前生成池塘壁纸") }
    precondition(image.width * 200 == image.height * 320, "壁纸必须使用屏幕比例，不能导出拉远后的世界边界")
    let rep = NSBitmapImageRep(cgImage: image)
    let center = rep.colorAt(x: image.width / 2, y: image.height / 2)!.usingColorSpace(.deviceRGB)!
    let edge = rep.colorAt(x: 0, y: 0)!.usingColorSpace(.deviceRGB)!
    precondition(center.redComponent > 0.9 && center.greenComponent < 0.1, "壁纸必须沿用相机位置与缩放，包含可见景物而非纯色")
    precondition(edge.greenComponent > edge.redComponent && edge.alphaComponent == 1, "壁纸边缘必须保持不透明池水底色")
    // The red marker is 20 points wide after zooming out, not its 40-point world size.
    let outside = rep.colorAt(x: image.width / 2 + image.width * 15 / 320, y: image.height / 2)!.usingColorSpace(.deviceRGB)!
    precondition(outside.greenComponent > outside.redComponent, "壁纸和动画必须采用相同的相机缩放")
    let storage = FileManager.default.temporaryDirectory.appendingPathComponent("pond-wallpaper-check-\(UUID().uuidString)", isDirectory: true)
    try! FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: storage); view.presentScene(nil); window.close() }
    let first = WallpaperSync.imageURL(image: image, screenID: "test", current: nil, in: storage)!
    let second = WallpaperSync.imageURL(image: image, screenID: "test", current: first, in: storage)!
    let third = WallpaperSync.imageURL(image: image, screenID: "test", current: second, in: storage)!
    precondition(first != second && third == first, "更新壁纸必须切换路径让系统刷新，并限制文件数量")
    let loaded = NSImage(contentsOf: second)!
    precondition(loaded.representations.first?.pixelsWide == image.width, "保存的池塘壁纸必须保留完整分辨率")
    precondition((try! FileManager.default.contentsOfDirectory(at: storage, includingPropertiesForKeys: nil)).count == 2, "壁纸更新不能无限积累图片")
    print("通过：提前生成池塘壁纸、屏幕比例、相机位置与缩放、不透明池水底色、高清 PNG 和双文件复用；未修改系统壁纸。")
}

func runDesktopPresentationChecks(preferences: Preferences) {
    let size = CGSize(width: 640, height: 400)
    let window = DesktopWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let canvas = DesktopPondView(frame: CGRect(origin: .zero, size: size))
    window.contentView = canvas
    let scene = PondScene(size: size, preferences: preferences)
    canvas.renderer.presentScene(scene)
    defer { canvas.renderer.presentScene(nil); window.close() }
    let start = Date()
    precondition(canvas.updateBackdrop(), "窗口显示前必须先准备完整池塘底图")
    let initialDuration = Date().timeIntervalSince(start)
    let image = canvas.backdrop!
    precondition(canvas.layer?.contents != nil, "池塘底图必须存在于窗口自身，而不是只更换系统壁纸")
    precondition(canvas.renderer.allowsTransparency, "恢复绘制时必须透出池塘底图")
    precondition(scene.backgroundColor.alphaComponent == 0, "动态画布不能用纯绿色遮住窗口底图")
    let pixels = NSBitmapImageRep(cgImage: image)
    precondition(pixels.colorAt(x: 0, y: 0)!.alphaComponent == 1, "窗口池塘底图必须不透明")
    let cachedStart = Date()
    for _ in 0..<100 { precondition(canvas.updateBackdrop()) }
    let cachedDuration = Date().timeIntervalSince(cachedStart)
    precondition(canvas.backdrop === image, "空间切换必须复用已有底图，不能反复截图和编码")
    let oldStamp = canvas.backdropStamp
    preferences.designs[0].size += 0.01; scene.configure()
    precondition(canvas.updateBackdrop() && canvas.backdropStamp != oldStamp, "修改金鱼外观后必须更新窗口底图")
    let updated = canvas.backdrop
    canvas.renderer.isHidden = true; canvas.renderer.presentScene(nil)
    precondition(canvas.backdrop === updated && canvas.layer?.contents != nil, "动态渲染器暂不可用时，窗口必须仍然保留池塘画面")
    precondition(WallpaperSync.isManaged(WallpaperSync.directory.appendingPathComponent("water-385E50.png")), "空间切换必须识别旧版绿色壁纸")
    precondition(!WallpaperSync.isManaged(URL(fileURLWithPath: "/tmp/user-wallpaper.png")), "空间切换不应更改其他空间的用户壁纸")
    print(String(format: "通过：窗口内完整池塘底图、透明动态画布、外观更新、渲染器不可用时保留画面及旧壁纸识别；生成 %.1f ms，100 次缓存复用 %.1f ms。", initialDuration * 1000, cachedDuration * 1000))
}

func runDesignChecks(preferences: Preferences) {
    let editor = FishEditorState(preferences: preferences)
    editor.remember()
    editor.draft.bodyColor = 0x407E50
    editor.draft.finColor = 0x9FA862
    editor.draft.size = 0.68
    editor.draft.variant = -1
    editor.draft.strokes = [PaintStroke(points: [PaintPoint(x: -120, y: 0), PaintPoint(x: 120, y: 0)], color: 0xD44030, width: 9)]
    editor.flush()
    let edited = editor.draft
    editor.select(1)
    precondition(preferences.designs[0] == edited, "切换金鱼前必须保存当前外观")
    precondition(preferences.designs[1] == FishDesign.initial(1), "单尾外观不能改变其他鱼")
    let loaded = Preferences(defaults: preferences.defaults)
    precondition(loaded.designs[0] == edited, "重新启动后必须恢复颜色、大小和笔画")
    editor.select(0); editor.remember(); editor.clearPattern(); editor.undo()
    precondition(editor.draft.strokes == edited.strokes, "撤销必须恢复花纹")
    editor.redo(); precondition(editor.draft.strokes.isEmpty, "重做必须再次清空花纹")
    editor.draft = edited
    let bounds = FishPainter.bodyBounds
    func pixel(_ image: CGImage, x: Double, y: Double) -> [UInt8] {
        let bytes = image.dataProvider!.data! as Data
        let column = Int((x - bounds.minX) * 4), row = Int((y - bounds.minY) * 4)
        let offset = row * image.bytesPerRow + column * 4
        return Array(bytes[offset..<(offset + 4)])
    }
    let painted = bitmap(bounds: bounds, scale: 4) { FishPainter.drawBody($0, design: edited) }
    precondition(pixel(painted, x: 42, y: 22)[3] == 0, "花纹必须被裁切在鱼身轮廓内")
    let red = pixel(painted, x: 2, y: 0)
    precondition(red[0] > red[1], "画笔必须真实改变鱼身纹理")
    var erased = edited
    erased.strokes.append(PaintStroke(points: [PaintPoint(x: 2, y: -12), PaintPoint(x: 2, y: 12)], color: 0, width: 7, erases: true))
    let cleaned = bitmap(bounds: bounds, scale: 4) { FishPainter.drawBody($0, design: erased) }
    let green = pixel(cleaned, x: 2, y: 0)
    precondition(green[1] > green[0], "橡皮必须恢复鱼身底色")
    preferences.designs[0] = edited
    let scene = PondScene(size: CGSize(width: 900, height: 600), preferences: preferences)
    let beforeZero = scene.swimmers.map { CGPoint(x: $0.x, y: $0.y) }
    scene.size = .zero; scene.update(1); scene.update(2)
    precondition(scene.swimmers.map { CGPoint(x: $0.x, y: $0.y) } == beforeZero, "窗口尚未布局时不能把鱼挤到原点")
    scene.size = CGSize(width: 900, height: 600)
    let first = scene.fishNodes[0]
    precondition(abs(first.xScale - scene.swimmers[0].length / 115 * 0.68) < 0.0001, "自定义大小必须用于真实鱼群")
    let priorKey = first.designKey
    preferences.designs[0] = erased; scene.configure()
    precondition(scene.fishNodes[0].designKey != priorKey, "修改花纹必须更新池塘中的鱼")
    scene.feed(at: CGPoint(x: scene.worldSize.width * 0.5, y: scene.worldSize.height * 0.4))
    preferences.distance = 2.4; scene.configure()
    precondition(abs(scene.pondCamera.xScale - 2.4) < 0.0001)
    precondition(scene.worldSize.width == 2160 && scene.worldSize.height == 1440)
    precondition(scene.swimmers.allSatisfy { $0.x >= 0 && $0.x <= scene.worldSize.width && $0.y >= 0 && $0.y <= scene.worldSize.height }, "拉远视野不能把鱼移出池塘")
    precondition(abs(scene.foodSpots[0].position.x - scene.worldSize.width * 0.5) < 0.001, "调整视野时投喂位置必须随池塘缩放")
    runVegetationChecks()
    runInteractionChecks(preferences: preferences)
    runWaterChecks(preferences: preferences)
    runDaylightChecks(preferences: preferences)
    runPlantMotionChecks(preferences: preferences)
    runCritterChecks(preferences: preferences)
    runDesktopPresentationChecks(preferences: preferences)
    print("通过：单尾颜色/大小/笔画持久化、鱼身裁切、橡皮底色恢复、撤销重做、鱼群纹理更新、相机缩放和零尺寸窗口保护。")
}

func runDaylightChecks(preferences: Preferences) {
    let calendar = Calendar.current
    func at(_ hour: Int) -> Date { calendar.date(from: DateComponents(hour: hour, minute: 30))! }
    for (hour, key) in [(0, "night"), (3, "night"), (4, "dawn"), (10, "dawn"), (11, "noon"), (16, "noon"), (17, "dusk"), (19, "dusk"), (20, "night"), (23, "night")] {
        precondition(Daylight.effective(mode: "auto", date: at(hour)).key == key, "自动时段必须在 \(hour) 点半映射到 \(key)")
    }
    for (mode, key) in [("dawn", "dawn"), ("noon", "noon"), ("dusk", "dusk"), ("night", "night")] {
        precondition(Daylight.effective(mode: mode, date: at(12)).key == key, "手动时段必须优先于时钟")
    }
    func luminance(_ hex: UInt32) -> Double {
        Double((hex >> 16) & 255) * 0.3 + Double((hex >> 8) & 255) * 0.6 + Double(hex & 255) * 0.1
    }
    let noonPalette = Palette(theme: "jade", daylight: .noon)
    precondition(noonPalette.water == 0x385E50 && noonPalette.silt == 0x737F59, "中午必须保持主题原色")
    let nightWater = Palette(theme: "jade", daylight: .night).water
    let dawnWater = Palette(theme: "jade", daylight: .dawn).water
    let duskWater = Palette(theme: "jade", daylight: .dusk).water
    precondition(luminance(nightWater) < luminance(dawnWater) && luminance(dawnWater) < luminance(noonPalette.water), "夜晚必须比凌晨暗，凌晨比中午暗")
    precondition((nightWater & 255) > ((nightWater >> 16) & 255), "夜晚水色必须偏冷蓝")
    precondition(((duskWater >> 16) & 255) > (duskWater & 255), "傍晚水色必须偏暖")
    func meanLuminance(_ image: CGImage) -> Double {
        let rep = NSBitmapImageRep(cgImage: image)
        var total = 0.0
        for y in stride(from: 0, to: rep.pixelsHigh, by: 24) {
            for x in stride(from: 0, to: rep.pixelsWide, by: 24) {
                let sample = rep.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                total += Double(sample.redComponent + sample.greenComponent + sample.blueComponent)
            }
        }
        return total
    }
    let world = CGSize(width: 1440, height: 900)
    let noonBed = PondEnvironment.make(size: world, density: 1.15, palette: noonPalette, daylight: .noon, rasterScale: 1).bed
    let nightBed = PondEnvironment.make(size: world, density: 1.15, palette: Palette(theme: "jade", daylight: .night), daylight: .night, rasterScale: 1).bed
    precondition(meanLuminance(nightBed) < meanLuminance(noonBed) * 0.8, "夜晚的池底烘焙必须明显变暗")
    preferences.daylightMode = "night"
    let scene = PondScene(size: world, preferences: preferences)
    precondition(scene.floorStamp.contains("night"), "池底缓存签名必须包含时段")
    precondition(scene.fishNodes[0].daylightBlend > 0.1, "夜晚的金鱼必须压暗")
    precondition(scene.water.glints.first!.sprite.colorBlendFactor > 0.3, "夜晚的反光必须染成月光色")
    let floating = scene.plantMotions.first { !$0.placement.submerged }!
    precondition(floating.sprite.colorBlendFactor > 0.1, "夜晚的浮叶必须带时段色")
    let nightStamp = scene.floorStamp
    preferences.daylightMode = "noon"
    scene.configure()
    precondition(scene.floorStamp != nightStamp, "时段变化必须重建池底")
    precondition(scene.fishNodes[0].daylightBlend == 0, "中午的金鱼不能带时段色")
    print("通过：时段映射覆盖全天、中午恒等、夜晚更暗更冷、傍晚偏暖、池底压暗烘焙，以及鱼/浮叶/反光的时段染色与签名重建。")
}

func runWaterChecks(preferences: Preferences) {
    let size = CGSize(width: 640, height: 400)
    let window = DesktopWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let view = SKView(frame: CGRect(origin: .zero, size: size)); window.contentView = view
    let scene = PondScene(size: size, preferences: preferences); view.presentScene(scene)
    defer { view.presentScene(nil); window.close() }
    scene.inhabitants.isHidden = true
    scene.water.configure(size: scene.worldSize, distance: preferences.distance, bed: scene.bedSprite!, floor: scene.floor, surface: scene.surface, reducedMotion: false)
    func frame(_ time: Double) -> CGImage {
        scene.water.update(time: time)
        return WallpaperSync.snapshotImage(view: view, scene: scene)!
    }
    func difference(_ a: CGImage, _ b: CGImage) -> Int {
        let a = NSBitmapImageRep(cgImage: a), b = NSBitmapImageRep(cgImage: b)
        var changed = 0
        for y in stride(from: 0, to: a.pixelsHigh, by: 5) {
            for x in stride(from: 0, to: a.pixelsWide, by: 5) {
                let first = a.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                let second = b.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                if abs(first.redComponent - second.redComponent) + abs(first.greenComponent - second.greenComponent) > 0.008 { changed += 1 }
            }
        }
        return changed
    }
    let first = frame(0), moving = frame(3)
    precondition(difference(first, moving) > 150, "水光和折射必须真实改变渲染像素，不能只有未生效的着色器参数")
    scene.water.reflections.isHidden = true
    let withoutGlints = frame(3)
    scene.water.reflections.isHidden = false
    let highlights = difference(withoutGlints, frame(3))
    precondition(highlights < first.width * first.height / 2500,
                 "反光只应影响少量像素，不能重新铺成密集的全屏光纹")
    let center = CGPoint(x: scene.worldSize.width / 2, y: scene.worldSize.height / 2)
    scene.water.addRipple(at: center, time: 3)
    let ripple = scene.water.ripples.last!
    scene.water.update(time: 5)
    precondition(ripple.calculateAccumulatedFrame().width / preferences.distance > 150, "视野拉远后涟漪仍应覆盖明显的屏幕范围")
    precondition(difference(moving, frame(5)) > 150)
    for _ in 0..<100 { scene.water.addRipple(at: center, time: 5) }
    precondition(scene.water.ripples.count <= 20, "连续移动鼠标必须限制波纹对象数量")
    scene.water.update(time: 15)
    precondition(scene.water.ripples.isEmpty && scene.water.rippleLayer.children.isEmpty, "消散的水波必须释放节点")
    scene.water.configure(size: scene.worldSize, distance: preferences.distance, bed: scene.bedSprite!, floor: scene.floor, surface: scene.surface, reducedMotion: true)
    let still = frame(15)
    precondition(difference(still, frame(20)) == 0, "减少动态效果时池底和水光应保持静止")
    scene.allowsFeeding = true
    let location = NSPoint(x: 220, y: 130)
    let tap = NSEvent.mouseEvent(with: .leftMouseDown, location: location, modifierFlags: [], timestamp: 0,
                               windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
    scene.mouseDown(with: tap)
    let expected = scene.worldPoint(fromView: location)
    let spot = scene.foodSpots.last!
    precondition(hypot(spot.position.x - expected.x, spot.position.y - expected.y) < 0.01,
                 "预览点击只能做一次相机换算，投喂与水波必须落在光标位置")
    let old = scene.simulationTime
    preferences.paused = true; scene.update(100); scene.update(101)
    precondition(scene.simulationTime == old, "暂停时水波和水面必须一起停止")
    preferences.paused = false
    // 与水面无关的设置变更走 configure 时，进行中的涟漪和反光节点必须原样保留。
    scene.water.addRipple(at: center, time: 30)
    let ripplesBefore = scene.water.ripples.count
    let glintSprites = scene.water.glints.map { $0.sprite }
    scene.configure()
    precondition(scene.water.ripples.count == ripplesBefore, "非水面相关的设置变更不能清掉进行中的涟漪")
    precondition(scene.water.glints.map { $0.sprite } == glintSprites, "反光节点必须跨 configure 复用，不能随无关设置重建")
    // 视野变化必须真正重建水面，清理旧坐标里的波纹。
    let originalDistance = preferences.distance
    preferences.distance = 1.0; scene.configure()
    precondition(scene.water.ripples.isEmpty, "视野变化必须清理旧坐标的波纹")
    precondition(scene.water.glints.map { $0.sprite } != glintSprites, "视野变化必须重建水面")
    preferences.distance = originalDistance; scene.configure()
    print("通过：水面着色器真实像素变化、大范围涟漪、连续互动节点上限、消散清理、减少动态效果、暂停，以及无关设置保留涟漪、视野变化重建水面。")
}

func runPlantMotionChecks(preferences: Preferences) {
    let scene = PondScene(size: CGSize(width: 900, height: 600), preferences: preferences)
    let motions = scene.plantMotions
    precondition(Set(motions.map { $0.placement.kind }).count == AquaticPlant.allCases.count)
    let textures = motions.map { $0.sprite.texture! }
    for motion in motions { motion.animate(time: 0, distance: preferences.distance, reducedMotion: false) }
    let initial = motions.map { $0.sprite.position }
    for motion in motions { motion.animate(time: 5, distance: preferences.distance, reducedMotion: false) }
    let movingLeaves = zip(motions, initial).filter { motion, first in
        !motion.placement.submerged && hypot(motion.sprite.position.x - first.x, motion.sprite.position.y - first.y) / preferences.distance > 1
    }
    precondition(movingLeaves.count > 5, "浮叶、花与浮萍必须真实改变位置，运动在屏幕上应可见")
    for frame in 0..<240 {
        for motion in motions {
            motion.animate(time: Double(frame) * 0.5, distance: preferences.distance, reducedMotion: false)
            let offset = hypot(motion.sprite.position.x - motion.placement.position.x,
                               motion.sprite.position.y - motion.placement.position.y) / preferences.distance
            precondition(offset < 12, "植物长时间运动不能离开原来的群落")
            if motion.placement.submerged {
                let warp = motion.sprite.warpGeometry as! SKWarpGeometryGrid
                precondition(warp.destPosition(at: 2) == warp.sourcePosition(at: 2) &&
                             warp.destPosition(at: 3) == warp.sourcePosition(at: 3), "水草茎根必须固定，只弯动叶梢")
                precondition(hypot(motion.sprite.position.x - motion.placement.position.x,
                                   motion.sprite.position.y - motion.placement.position.y) < 0.001,
                             "水草根部位置应保持固定（允许 SpriteKit 单精度存储误差）")
            }
        }
    }
    let plantCount = motions.count
    scene.update(1); scene.update(2)
    let posed = motions.map { $0.sprite.position }
    preferences.paused = true; scene.update(3)
    precondition(motions.map { $0.sprite.position } == posed, "暂停鱼群时植物也必须停止")
    preferences.paused = false
    for (index, motion) in motions.enumerated() {
        motion.animate(time: 200, distance: preferences.distance, reducedMotion: true)
        precondition(hypot(motion.sprite.position.x - motion.placement.position.x,
                           motion.sprite.position.y - motion.placement.position.y) < 0.001 && motion.sprite.warpGeometry == nil,
                     "减少动态效果时植物恢复静态形态")
        precondition(motion.sprite.texture === textures[index], "植物动画必须复用高清纹理")
    }
    precondition(scene.plantMotions.count == plantCount, "动画不能增加植物节点")
    print("通过：六类植物可见运动、两分钟漂移边界、水草根部固定、暂停、减少动态效果与纹理复用。")
}

func runCritterChecks(preferences: Preferences) {
    // 乌龟：60 秒模拟的有限值、边界、平缓转向与周期换气。
    var turtle = TurtleBrain(x: 500, y: 400, angle: 0.3, cruise: 11, phase: 2.1)
    var breaths = 0
    for frame in 0..<1800 {
        if turtle.step(dt: 1.0 / 30, time: Double(frame) / 30, width: 2376, height: 1485, speed: 0.8, targets: []) { breaths += 1 }
        precondition(turtle.x.isFinite && turtle.y.isFinite && turtle.angle.isFinite, "乌龟状态必须为有限数")
        precondition(turtle.x >= 30 && turtle.x <= 2346 && turtle.y >= 30 && turtle.y <= 1455, "乌龟不能越过边界")
        precondition(abs(turtle.turn) <= 0.56, "乌龟转向必须平缓")
    }
    precondition(breaths >= 2, "乌龟必须周期性上浮换气")
    // 乌龟认食：30 秒内慢慢挪到饲料附近，不冲刺。
    var fed = TurtleBrain(x: 500, y: 400, angle: 0, cruise: 12, phase: 0.5)
    let food = CGPoint(x: 640, y: 400)
    for frame in 0..<900 {
        _ = fed.step(dt: 1.0 / 30, time: Double(frame) / 30, width: 1440, height: 900, speed: 1.0, targets: [food])
    }
    precondition(hypot(fed.x - food.x, fed.y - food.y) < 40, "乌龟必须慢慢游向饲料")
    // 蝌蚪：30 秒模拟保持松散群落，不越界。
    var rng = SeededRandom()
    var school = (0..<8).map { _ in TadpoleBrain(x: rng.range(300, 700), y: rng.range(200, 500), angle: rng.range(0, tau), cruise: rng.range(26, 40), phase: rng.range(0, tau)) }
    for frame in 0..<900 {
        let time = Double(frame) / 30
        var center = CGPoint.zero
        for member in school { center.x += member.x; center.y += member.y }
        center.x /= Double(school.count); center.y /= Double(school.count)
        let positions = school.map { CGPoint(x: $0.x, y: $0.y) }
        for i in school.indices {
            var neighbors: [CGPoint] = []
            for (j, p) in positions.enumerated() where j != i { neighbors.append(p) }
            school[i].step(dt: 1.0 / 30, time: time, width: 1000, height: 700, speed: 1.0, center: center, neighbors: neighbors)
            precondition(school[i].x.isFinite && school[i].x >= 16 && school[i].x <= 984 && school[i].y >= 16 && school[i].y <= 684, "蝌蚪不能越过边界")
        }
    }
    let xs = school.map { $0.x }, ys = school.map { $0.y }
    precondition((xs.max()! - xs.min()!) < 620 && (ys.max()! - ys.min()!) < 620, "蝌蚪必须保持松散群落，不能散满全池")
    precondition(TurtlePainter.parts(1).first!.texture === TurtlePainter.parts(1).first!.texture, "乌龟必须复用纹理缓存")
    precondition(TadpolePainter.part(0).texture === TadpolePainter.part(0).texture && SnailPainter.part(0).texture === SnailPainter.part(0).texture, "蝌蚪与田螺必须复用纹理缓存")
    // 场景级：生成数量、独立图层、惊吓、暂停、开关、视野缩放与时段染色。
    let scene = PondScene(size: CGSize(width: 900, height: 600), preferences: preferences)
    scene.update(1); scene.update(2)
    precondition(scene.critters.turtles.count == 2, "默认必须有两只小乌龟")
    precondition(scene.critters.tadpoles.count >= 4 && scene.critters.tadpoles.count <= 10, "蝌蚪数量必须随池塘面积取整")
    precondition(scene.critters.snails.count >= 1 && scene.critters.snails.count <= 3, "田螺数量必须在 1–3 只之间")
    let critterCount = scene.critters.turtles.count + scene.critters.tadpoles.count + scene.critters.snails.count
    precondition(scene.critterLayer.children.count == critterCount, "小动物必须挂在独立图层")
    precondition(scene.critters.turtles.allSatisfy { $0.node.children.count == 5 } &&
                 scene.critters.tadpoles.allSatisfy { $0.node.children.count == 1 } &&
                 scene.critters.snails.allSatisfy { $0.node.children.count == 1 }, "每只小动物都必须挂上贴图子节点")
    let victim = scene.critters.tadpoles[0]
    let scare = CGPoint(x: victim.brain.x + 12, y: victim.brain.y)
    scene.startle(near: scare)
    precondition(scene.critters.tadpoles[0].brain.startledUntil > scene.simulationTime, "惊吓半径内的蝌蚪必须被惊到")
    let fledFrom = CGPoint(x: scene.critters.tadpoles[0].brain.x, y: scene.critters.tadpoles[0].brain.y)
    for frame in 0..<30 { scene.update(Double(frame) / 30 + 10) }
    let fled = CGPoint(x: scene.critters.tadpoles[0].brain.x, y: scene.critters.tadpoles[0].brain.y)
    precondition(hypot(fled.x - scare.x, fled.y - scare.y) > hypot(fledFrom.x - scare.x, fledFrom.y - scare.y), "受惊的蝌蚪必须远离惊吓点")
    let untouched = scene.critters.tadpoles.map { $0.brain.startledUntil }
    scene.startle(near: CGPoint(x: -9000, y: -9000))
    precondition(scene.critters.tadpoles.map { $0.brain.startledUntil } == untouched, "远离池塘的惊吓不应影响蝌蚪")
    let posed = scene.critters.turtles.map { CGPoint(x: $0.brain.x, y: $0.brain.y) }
    let still = scene.critters.snails.map { CGPoint(x: $0.brain.x, y: $0.brain.y) }
    preferences.paused = true; scene.update(50); scene.update(51)
    precondition(scene.critters.turtles.map { CGPoint(x: $0.brain.x, y: $0.brain.y) } == posed &&
                 scene.critters.snails.map { CGPoint(x: $0.brain.x, y: $0.brain.y) } == still, "暂停时小动物也必须停止")
    preferences.paused = false
    preferences.critters = false; scene.configure()
    precondition(scene.critterLayer.children.isEmpty && scene.critters.isEmpty, "关闭小乌龟与小邻居必须清场")
    preferences.critters = true; scene.configure()
    precondition(!scene.critters.turtles.isEmpty && !scene.critters.tadpoles.isEmpty && !scene.critters.snails.isEmpty, "重新打开必须恢复小动物")
    let oldWorld = scene.worldSize
    let turtleBefore = scene.critters.turtles[0].brain
    let tadpoleBefore = scene.critters.tadpoles[0].brain
    scene.size = CGSize(width: 1800, height: 1200); scene.configure()
    let ratio = scene.worldSize.width / oldWorld.width
    precondition(abs(scene.critters.turtles[0].brain.x - turtleBefore.x * ratio) < 0.001 &&
                 abs(scene.critters.tadpoles[0].brain.y - tadpoleBefore.y * ratio) < 0.001, "调整视野时小动物必须随池塘缩放")
    precondition(scene.critters.turtles[0].brain.x <= scene.worldSize.width - 30, "缩放后的乌龟不能越过新边界")
    preferences.daylightMode = "night"; scene.configure()
    precondition(scene.critters.turtles[0].node.daylightBlend > 0.1, "夜晚的小动物必须带时段色")
    preferences.daylightMode = "noon"; scene.configure()
    precondition(scene.critters.turtles[0].node.daylightBlend == 0, "中午的小动物不能带时段色")
    print("通过：乌龟换气与认食、蝌蚪群落与受惊四散、田螺爬行、暂停、开关清场、视野缩放、纹理复用与时段染色。")
}

func runVegetationChecks() {
    for viewport in [CGSize(width: 800, height: 600), CGSize(width: 1440, height: 900), CGSize(width: 3440, height: 1440)] {
        for distance in [1.0, 1.65, 2.4] {
            let world = CGSize(width: viewport.width * distance, height: viewport.height * distance)
            let innerWater = CGRect(x: world.width * 0.15, y: world.height * 0.15, width: world.width * 0.7, height: world.height * 0.7)
            for density in [0.5, 1.15, 1.8] {
                let vegetation = PondEnvironment.placements(size: world, density: density)
                let leaves = vegetation.filter { $0.kind == .lotus || $0.kind == .lily }
                precondition(leaves.filter { innerWater.contains($0.position) }.count >= 6, "疏朗模式和远眺视野也必须在池塘内部保留植物")
                precondition(vegetation.contains { $0.submerged && innerWater.contains($0.position) }, "内部植被必须包含鱼群下方的沉水草")
                let widths = leaves.map { 190 * Double($0.scale) / distance }.sorted()
                precondition(widths[widths.count / 2] >= 65, "植物不能随拉远视野缩成难以辨认的小图案")
            }
            let sparse = PondEnvironment.placements(size: world, density: 0.5)
            let dense = PondEnvironment.placements(size: world, density: 1.8)
            precondition(sparse.allSatisfy { plant in dense.contains { $0.kind == plant.kind && $0.position == plant.position && $0.scale == plant.scale } }, "丰茂度只增加植被，不应重新随机移动已有植物")
        }
    }
    for kind in AquaticPlant.allCases {
        let art = PlantPainter.art(kind, variant: 0)
        precondition(art.texture.cgImage().width >= Int(art.bounds.width * 4), "植物必须使用独立高清纹理，不受整张池塘分辨率限制")
        precondition(art.texture === PlantPainter.art(kind, variant: 0).texture, "同种植物必须复用纹理，避免重复占用内存")
    }
    print("通过：3 种屏幕 × 3 档视野 × 3 档丰茂度的内部植被、可见尺寸、稳定分布与独立高清纹理缓存。")
}

func runInteractionChecks(preferences: Preferences) {
    let stream = CursorStream()
    var ripples = 0
    for i in 0..<20 { if stream.moved(to: NSPoint(x: Double(i) * 5, y: 3), at: Double(i) * 0.05) != nil { ripples += 1 } }
    precondition(ripples >= 2 && ripples <= 6, "缓动光标应按间距泛起涟漪，而不是每帧刷屏")
    precondition(!stream.startled(at: 1.1), "缓动不应惊吓鱼群")
    _ = stream.moved(to: NSPoint(x: 700, y: 3), at: 1.13)
    precondition(stream.startled(at: 1.13), "急挥必须惊散鱼群")
    precondition(!stream.startled(at: 1.14), "同一次急挥只惊吓一次")
    stream.pressed(to: NSPoint(x: 10, y: 10), at: 2); stream.dragged(to: NSPoint(x: 80, y: 10))
    precondition(stream.released(at: 2.2) == nil, "拖拽框选或拖文件不应投喂")
    stream.pressed(to: NSPoint(x: 10, y: 10), at: 3)
    precondition(stream.released(at: 3.15) == NSPoint(x: 10, y: 10), "桌面空白处的轻点应投喂")
    stream.pressed(to: NSPoint(x: 10, y: 10), at: 4)
    precondition(stream.released(at: 4.4) == nil, "长按不应投喂")
    let windows = [
        ScreenWindow(owner: "Safari", layer: 0, frame: NSRect(x: 0, y: 0, width: 500, height: 500)),
        ScreenWindow(owner: "Dock", layer: 20, frame: NSRect(x: 0, y: 0, width: 1000, height: 80)),
        ScreenWindow(owner: "Finder", layer: -2147483603, frame: NSRect(x: 0, y: 0, width: 1000, height: 800))
    ]
    precondition(isDesktopTap(NSPoint(x: 700, y: 400), windows: windows), "普通窗口之外的点击才算桌面")
    precondition(!isDesktopTap(NSPoint(x: 250, y: 250), windows: windows), "应用窗口内的点击不算桌面")
    precondition(!isDesktopTap(NSPoint(x: 500, y: 40), windows: windows), "程序坞上的点击不算桌面")
    precondition(isDesktopTap(NSPoint(x: 600, y: 500), windows: windows), "桌面图标所在的桌面层级不应拦截投喂")
    precondition(feedModifierFlag("option") == .option && feedModifierFlag("command") == .command && feedModifierName("shift") == "⇧", "投喂修饰键的映射与显示名必须正确")
    precondition(feedModifierActive([.option, .command], key: "option"), "按住投喂修饰键的轻点才应投喂")
    precondition(!feedModifierActive([.capsLock], key: "option"), "未按修饰键的普通点击不应投喂")
    preferences.distance = 2.4; preferences.interact = true
    let scene = PondScene(size: CGSize(width: 900, height: 600), preferences: preferences)
    scene.configure()
    let center = scene.worldPoint(fromView: CGPoint(x: 450, y: 300))
    precondition(abs(center.x - 1080) < 0.001 && abs(center.y - 720) < 0.001, "屏幕中心必须映射到池塘中心")
    let corner = scene.worldPoint(fromView: .zero)
    precondition(abs(corner.x) < 0.01 && abs(corner.y) < 0.01, "屏幕角落必须映射到池塘角落")
    let fish = scene.swimmers[0]
    var spot = CGPoint.zero
    for offset in [CGPoint(x: 260, y: 0), CGPoint(x: -260, y: 0), CGPoint(x: 0, y: 260), CGPoint(x: 0, y: -260)] {
        let candidate = CGPoint(x: fish.x + Double(offset.x), y: fish.y + Double(offset.y))
        if candidate.x >= 100 && candidate.x <= 2060 && candidate.y >= 100 && candidate.y <= 1340 { spot = candidate; break }
    }
    precondition(spot != .zero, "测试光标必须能放进池塘")
    scene.cursor = CursorProbe(world: spot, speed: 0, updated: Date())
    for frame in 0..<300 { scene.update(Double(frame) / 30 + 1) }
    let curious = scene.swimmers[0]
    precondition(hypot(curious.x - spot.x, curious.y - spot.y) < 200, "缓动的光标应吸引附近的金鱼靠近")
    scene.cursor = nil
    scene.startle(near: CGPoint(x: -4000, y: -4000))
    precondition(scene.swimmers.allSatisfy { $0.startledUntil == 0 }, "远离池塘的惊吓不应影响任何鱼")
    scene.swimmers[0].x = Double(spot.x + 150); scene.swimmers[0].y = Double(spot.y); scene.swimmers[0].angle = .pi
    scene.startle(near: spot)
    precondition(scene.swimmers[0].startledUntil > scene.simulationTime, "惊吓半径内的鱼必须被惊到")
    for frame in 0..<45 { scene.update(Double(frame) / 30 + 12) }
    precondition(cos(scene.swimmers[0].angle) > 0.3, "受惊的鱼必须转身逃离惊吓点")
    print("通过：涟漪节流、急挥惊散、轻点与拖拽区分、桌面空白判定、光标世界坐标换算、好奇靠近与受惊逃逸。")
}
