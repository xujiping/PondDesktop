import AppKit

// 光标在池塘世界坐标里的最新一帧，由事件监听写入，update 循环消费。
struct CursorProbe {
    let world: CGPoint
    let speed: Double
    let updated: Date
}

// 把原始鼠标采样整理成池塘意图：缓动的涟漪、急挥的惊吓、桌面空白的轻点。
// 只做纯计算，不接触事件系统，便于自测。
final class CursorStream {
    static let calmSpeed = 240.0     // 低于此速度视为“缓动”，泛涟漪、招好奇
    static let startleSpeed = 800.0  // 高于此速度视为“急挥”，惊散附近的鱼
    var speed = 0.0
    private var last: NSPoint?
    private var lastTime: TimeInterval = 0
    private var ripple: (point: NSPoint, time: TimeInterval)?
    private var startleCooldown: TimeInterval = -1
    private(set) var tap: (point: NSPoint, time: TimeInterval, anchor: NSPoint)?

    // 缓动时按路程与时间双重节流地吐出涟漪位置；急动不出涟漪。
    func moved(to p: NSPoint, at t: TimeInterval) -> NSPoint? {
        if let l = last, t > lastTime {
            speed = speed * 0.6 + hypot(p.x - l.x, p.y - l.y) / (t - lastTime) * 0.4
        }
        last = p; lastTime = t
        guard speed < Self.calmSpeed else { return nil }
        if let r = ripple, t - r.time < 0.13 || hypot(p.x - r.point.x, p.y - r.point.y) < 26 { return nil }
        ripple = (p, t)
        return p
    }

    // 一次急挥只惊吓一次，0.6 秒内不重复触发。
    func startled(at t: TimeInterval) -> Bool {
        guard speed > Self.startleSpeed, t > startleCooldown else { return false }
        startleCooldown = t + 0.6
        return true
    }

    func pressed(to p: NSPoint, at t: TimeInterval) { tap = (p, t, p) }
    // 位移超过 6 pt 视为拖拽（框选、拖文件），取消轻点候选。
    func dragged(to p: NSPoint) {
        if tap != nil, hypot(p.x - tap!.anchor.x, p.y - tap!.anchor.y) > 6 { tap = nil }
    }
    // 松开时若按住不足 0.35 秒且未拖拽，判定为一次桌面轻点。
    func released(at t: TimeInterval) -> NSPoint? {
        guard let held = tap else { return nil }
        tap = nil
        return t - held.time < 0.35 ? held.point : nil
    }
}

struct ScreenWindow {
    let owner: String
    let layer: Int
    let frame: NSRect  // 全局坐标（左下原点）
}

// 投喂修饰键：按住它轻点桌面空白处才投喂，普通点击完全不触发，
// 避免桌面的框选、多选等系统操作被顺带激活。
let feedModifierChoices: [(key: String, symbol: String)] = [("option", "⌥"), ("control", "⌃"), ("shift", "⇧"), ("command", "⌘")]
func feedModifierFlag(_ key: String) -> NSEvent.ModifierFlags {
    switch key {
    case "control": return .control
    case "shift": return .shift
    case "command": return .command
    default: return .option
    }
}
func feedModifierName(_ key: String) -> String {
    feedModifierChoices.first { $0.key == key }?.symbol ?? "⌥"
}
func feedModifierActive(_ flags: NSEvent.ModifierFlags, key: String) -> Bool {
    flags.contains(feedModifierFlag(key))
}

// 桌面空白处的判定：点击必须落在所有普通图层窗口（应用窗口、程序坞、菜单栏）之外。
// 桌面图标与壁纸位于桌面层级（layer < 0），不参与遮挡。
func isDesktopTap(_ point: NSPoint, windows: [ScreenWindow]) -> Bool {
    !windows.contains { $0.layer >= 0 && $0.frame.contains(point) }
}

extension AppDelegate {
    func installCursorInteraction() {
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseDown, .leftMouseUp]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] in self?.cursorEvent($0) }) { cursorMonitors.append(global) }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in self?.cursorEvent(event); return event }) { cursorMonitors.append(local) }
    }

    func cursorEvent(_ event: NSEvent) {
        guard preferences.enabled, preferences.interact, !systemSuspended, !desktopScenes.isEmpty else { return }
        let p = NSEvent.mouseLocation
        switch event.type {
        case .mouseMoved, .leftMouseDragged:
            if event.type == .leftMouseDragged { stream.dragged(to: p) }
            if let ripple = stream.moved(to: p, at: event.timestamp) {
                if let (scene, world) = desktopHit(ripple) { scene.addRipple(at: world) }
            }
            if stream.startled(at: event.timestamp) {
                if let (scene, world) = desktopHit(p) { scene.startle(near: world) }
            }
            let now = Date()
            for (window, scene) in zip(desktopWindows, desktopScenes) {
                if window.frame.contains(p) { scene.cursor = CursorProbe(world: scene.worldPoint(fromScreen: p) ?? .zero, speed: stream.speed, updated: now) }
                else { scene.cursor = nil }
            }
        case .leftMouseDown:
            if feedModifierActive(event.modifierFlags, key: preferences.feedModifier), desktopTapQualifies(at: p) { stream.pressed(to: p, at: event.timestamp) }
        case .leftMouseUp:
            if let tap = stream.released(at: event.timestamp), let (scene, world) = desktopHit(tap) { scene.feed(at: world) }
        default: break
        }
    }

    // 屏幕坐标 → 所在屏的池塘场景与世界坐标。
    func desktopHit(_ p: NSPoint) -> (PondScene, CGPoint)? {
        for (window, scene) in zip(desktopWindows, desktopScenes) {
            if window.frame.contains(p), let world = scene.worldPoint(fromScreen: p) { return (scene, world) }
        }
        return nil
    }

    // 点击落在所有可交互的普通窗口（应用窗口、程序坞、菜单栏）之外，就是桌面空点。
    // 桌面图标与壁纸位于桌面层级（layer < 0），不参与遮挡。
    // 程序坞有一块铺满整屏、忽略鼠标的背景窗口，点击会穿透到桌面，必须排除，
    // 否则屏幕上任何位置都判不成桌面。
    func desktopTapQualifies(at p: NSPoint) -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return false }
        let flip = NSScreen.screens.first?.frame.maxY ?? 0  // CG 窗口坐标以上左为原点，需翻转到 AppKit 坐标
        let screenArea = (NSScreen.screens.first { $0.frame.contains(p) } ?? NSScreen.screens.first)?.frame
            ?? NSRect(origin: .zero, size: .zero)
        var windows: [ScreenWindow] = []
        for info in list {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer >= 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let x = bounds["X"] as? Double, let y = bounds["Y"] as? Double,
                  let w = bounds["Width"] as? Double, let h = bounds["Height"] as? Double else { continue }
            let frame = NSRect(x: x, y: flip - y - h, width: w, height: h)
            if let pid = info[kCGWindowOwnerPID as String] as? Int32,
               NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == "com.apple.dock",
               frame.width * frame.height > screenArea.width * screenArea.height * 0.98 { continue }
            windows.append(ScreenWindow(owner: info[kCGWindowOwnerName as String] as? String ?? "", layer: layer,
                                        frame: frame))
        }
        return isDesktopTap(p, windows: windows)
    }
}
