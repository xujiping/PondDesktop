import AppKit

// The menu bar tint samples the system wallpaper itself, never overlay windows, so the only
// way to blend it with the pond is to temporarily install a solid wallpaper in the water
// colour and restore each screen's original image and options afterwards.
enum WallpaperSync {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("一池", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }
    static func solidImageURL(hex: UInt32) -> URL? {
        let url = directory.appendingPathComponent(String(format: "water-%06X.png", hex))
        guard !FileManager.default.fileExists(atPath: url.path) else { return url }
        let image = bitmap(bounds: CGRect(x: 0, y: 0, width: 8, height: 8), scale: 8) { ctx in
            ctx.setFillColor(color(hex).cgColor); ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return nil }
        do { try data.write(to: url); return url } catch { return nil }
    }
    static func key(_ screen: NSScreen) -> String? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue
    }
    static func apply(screens: [NSScreen], water: UInt32, defaults: UserDefaults) {
        guard let solid = solidImageURL(hex: water)?.standardizedFileURL else { return }
        var saved = defaults.dictionary(forKey: "savedWallpapers") as? [String: [String: Any]] ?? [:]
        for screen in screens {
            guard let id = key(screen), let current = NSWorkspace.shared.desktopImageURL(for: screen)?.standardizedFileURL else { continue }
            if current.path == solid.path { continue }
            if saved[id] == nil && !current.path.hasPrefix(directory.path + "/") { saved[id] = entry(for: current, screen: screen) }
            try? NSWorkspace.shared.setDesktopImageURL(solid, for: screen, options: [NSWorkspace.DesktopImageOptionKey(rawValue: "NSFillScreen"): true])
        }
        defaults.set(saved, forKey: "savedWallpapers")
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
