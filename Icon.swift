import AppKit
let icon = NSImage(size: NSSize(width: 1024, height: 1024))
icon.lockFocus()
NSColor(srgbRed: 0.14, green: 0.28, blue: 0.23, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 42, y: 42, width: 940, height: 940), xRadius: 208, yRadius: 208).fill()
NSColor(srgbRed: 0.31, green: 0.49, blue: 0.37, alpha: 1).setFill()
NSBezierPath(ovalIn: NSRect(x: 694, y: 705, width: 145, height: 145)).fill()
NSColor(srgbRed: 0.48, green: 0.62, blue: 0.41, alpha: 1).setStroke()
let vein = NSBezierPath(); vein.move(to: NSPoint(x: 766, y: 776)); vein.line(to: NSPoint(x: 719, y: 821)); vein.lineWidth = 3; vein.stroke()
func fish(x: CGFloat, y: CGFloat, angle: CGFloat, pale: Bool) {
    NSGraphicsContext.saveGraphicsState()
    let transform = NSAffineTransform(); transform.translateX(by: x, yBy: y); transform.rotate(byDegrees: angle); transform.concat()
    let amber = NSColor(srgbRed: 0.91, green: 0.51, blue: 0.26, alpha: 1)
    let cream = NSColor(srgbRed: 0.96, green: 0.91, blue: 0.77, alpha: 1)
    amber.setFill()
    let tail = NSBezierPath(); tail.move(to: NSPoint(x: -125, y: 0)); tail.curve(to: NSPoint(x: -245, y: 96), controlPoint1: NSPoint(x: -175, y: 8), controlPoint2: NSPoint(x: -162, y: 100)); tail.curve(to: NSPoint(x: -212, y: 0), controlPoint1: NSPoint(x: -276, y: 39), controlPoint2: NSPoint(x: -225, y: 29)); tail.curve(to: NSPoint(x: -245, y: -96), controlPoint1: NSPoint(x: -225, y: -29), controlPoint2: NSPoint(x: -276, y: -39)); tail.curve(to: NSPoint(x: -125, y: 0), controlPoint1: NSPoint(x: -162, y: -100), controlPoint2: NSPoint(x: -175, y: -8)); tail.fill()
    for sign: CGFloat in [-1, 1] {
        let fin = NSBezierPath(); fin.move(to: NSPoint(x: 31, y: sign * 39)); fin.curve(to: NSPoint(x: -63, y: sign * 120), controlPoint1: NSPoint(x: 8, y: sign * 109), controlPoint2: NSPoint(x: -38, y: sign * 129)); fin.curve(to: NSPoint(x: 31, y: sign * 39), controlPoint1: NSPoint(x: -79, y: sign * 57), controlPoint2: NSPoint(x: -23, y: sign * 25)); fin.fill()
    }
    (pale ? cream : amber).setFill()
    let body = NSBezierPath(); body.move(to: NSPoint(x: 156, y: 0)); body.curve(to: NSPoint(x: -130, y: 0), controlPoint1: NSPoint(x: 145, y: 111), controlPoint2: NSPoint(x: -79, y: 91)); body.curve(to: NSPoint(x: 156, y: 0), controlPoint1: NSPoint(x: -79, y: -91), controlPoint2: NSPoint(x: 145, y: -111)); body.fill()
    (pale ? amber : cream).setFill()
    NSBezierPath(ovalIn: NSRect(x: 10, y: -64, width: 71, height: 128)).fill()
    NSColor(srgbRed: 0.18, green: 0.24, blue: 0.19, alpha: 1).setFill()
    for sy: CGFloat in [-31, 31] { NSBezierPath(ovalIn: NSRect(x: 106, y: sy - 8, width: 18, height: 16)).fill() }
    NSGraphicsContext.restoreGraphicsState()
}
fish(x: 470, y: 638, angle: 23, pale: false)
fish(x: 582, y: 369, angle: 203, pale: true)
NSColor(srgbRed: 0.70, green: 0.78, blue: 0.65, alpha: 0.5).setStroke()
let ripple = NSBezierPath(ovalIn: NSRect(x: 777, y: 260, width: 66, height: 66)); ripple.lineWidth = 4; ripple.stroke()
icon.unlockFocus()
let rep = NSBitmapImageRep(data: icon.tiffRepresentation!)!
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
