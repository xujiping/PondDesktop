import AppKit
import SpriteKit
import QuartzCore

// WindowServer can reveal an AppKit window before SpriteKit has a new drawable.
// Keep an opaque pond image in the window's own backing layer through that gap.
final class DesktopPondView: NSView {
    let renderer: SKView
    private(set) var backdrop: CGImage?
    private(set) var backdropStamp = ""

    override init(frame frameRect: NSRect) {
        renderer = SKView(frame: CGRect(origin: .zero, size: frameRect.size))
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.contentsGravity = .resize
        renderer.autoresizingMask = [.width, .height]
        renderer.allowsTransparency = true
        renderer.ignoresSiblingOrder = true
        addSubview(renderer)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @discardableResult func updateBackdrop() -> Bool {
        guard let scene = renderer.scene as? PondScene else { return false }
        let stamp = WallpaperSync.stamp(for: scene)
        if backdrop != nil && backdropStamp == stamp { return true }
        guard let image = WallpaperSync.snapshotImage(view: renderer, scene: scene) else { return false }
        backdrop = image; backdropStamp = stamp
        CATransaction.begin(); CATransaction.setDisableActions(true)
        layer?.contents = image
        layer?.contentsScale = window?.backingScaleFactor ?? 2
        CATransaction.commit()
        return true
    }
}
