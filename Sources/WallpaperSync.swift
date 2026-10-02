import AppKit
import SpriteKit

// Space transitions show the system wallpaper before desktop-level windows. Keep a
// camera-matched pond frame underneath the animation, also used for menu bar tinting.
enum WallpaperSync {
    static var snapshots: [String: (stamp: String, url: URL)] = [:]
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("一池", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }
    static func snapshotImage(view: SKView, scene: SKScene) -> CGImage? {
        guard scene.size.width > 0, scene.size.height > 0 else { return nil }
        // An explicit viewport crop includes the active camera and avoids exporting
        // the larger world bounds when the user has zoomed out.
        return view.texture(from: scene, crop: CGRect(origin: .zero, size: scene.size))?.cgImage()
    }
    static func imageURL(image: CGImage, screenID: String, current: URL?, in storage: URL = directory) -> URL? {
        // Alternate two paths so macOS reloads changed pixels without accumulating files.
        let first = "pond-\(screenID)-a.png"
        let filename = current?.lastPathComponent == first ? "pond-\(screenID)-b.png" : first
        let url = storage.appendingPathComponent(filename)
        guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return nil }
        do { try data.write(to: url, options: .atomic); return url } catch { return nil }
    }
    static func key(_ screen: NSScreen) -> String? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue
    }
    static func stamp(for scene: PondScene) -> String {
        let fish = scene.fishNodes.map { "\($0.designKey):\($0.xScale)" }.joined(separator: "|")
        return "\(scene.floorStamp)|\(scene.size)|\(scene.preferences.distance)|\(fish)"
    }
    static func isManaged(_ url: URL) -> Bool {
        url.standardizedFileURL.path.hasPrefix(directory.standardizedFileURL.path + "/")
    }
    static func apply(screen: NSScreen, frame: CGImage, stamp: String, defaults: UserDefaults, onlyManaged: Bool = false) {
        guard let id = key(screen), let current = NSWorkspace.shared.desktopImageURL(for: screen)?.standardizedFileURL else { return }
        // Wallpaper selection belongs to a Space, not just a physical screen. On
        // Space changes upgrade our old green wallpapers, leaving unrelated ones alone.
        guard !onlyManaged || isManaged(current) else { return }
        let image: URL
        if let cached = snapshots[id], cached.stamp == stamp {
            image = cached.url
        } else {
            guard let url = imageURL(image: frame, screenID: id, current: current)?.standardizedFileURL else { return }
            image = url; snapshots[id] = (stamp, url)
        }
        guard current != image else { return }
        var saved = defaults.dictionary(forKey: "savedWallpapers") as? [String: [String: Any]] ?? [:]
        // The old solid wallpapers live in the same directory: retain their original
        // backup during upgrades, and persist it before changing the system wallpaper.
        if saved[id] == nil && !isManaged(current) { saved[id] = entry(for: current, screen: screen) }
        defaults.set(saved, forKey: "savedWallpapers")
        try? NSWorkspace.shared.setDesktopImageURL(image, for: screen, options: [NSWorkspace.DesktopImageOptionKey(rawValue: "NSFillScreen"): true])
    }
    static func entry(for image: URL, screen: NSScreen) -> [String: Any] {
        var entry: [String: Any] = ["path": image.path]
        if let options = NSWorkspace.shared.desktopImageOptions(for: screen) {
            var stored: [String: Any] = [:]
            for (k, v) in options where v is NSNumber { stored[k.rawValue] = v }
            if !stored.isEmpty { entry["options"] = stored }
        }
        return entry
    }
    static func restore(defaults: UserDefaults) {
        var saved = defaults.dictionary(forKey: "savedWallpapers") as? [String: [String: Any]] ?? [:]
        guard !saved.isEmpty else { return }
        for screen in NSScreen.screens {
            guard let id = key(screen), let record = saved[id], let path = record["path"] as? String else { continue }
            var options: [NSWorkspace.DesktopImageOptionKey: Any] = [:]
            if let stored = record["options"] as? [String: Any] {
                for (k, v) in stored { options[NSWorkspace.DesktopImageOptionKey(rawValue: k)] = v }
            }
            if (try? NSWorkspace.shared.setDesktopImageURL(URL(fileURLWithPath: path), for: screen, options: options)) != nil { saved[id] = nil }
        }
        // Screens that are unplugged keep their record so a later relaunch can still restore them.
        if saved.isEmpty { defaults.removeObject(forKey: "savedWallpapers") }
        else { defaults.set(saved, forKey: "savedWallpapers") }
    }
}
