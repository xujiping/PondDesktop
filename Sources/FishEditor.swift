import AppKit
import SwiftUI


final class FishEditorState: ObservableObject {
    let preferences: Preferences
    @Published var selected: Int = 0
    @Published var draft: FishDesign { didSet { scheduleSave() } }
    @Published var brushColor: UInt32 = 0xF5E8CE
    @Published var brushWidth: Double = 4
    @Published var eraser = false
    @Published var notice = "花纹和颜色自动保存，桌面的金鱼同步更新。"
    @Published var history: [FishDesign] = []
    @Published var future: [FishDesign] = []
    var pending: DispatchWorkItem?
    init(preferences: Preferences) { self.preferences = preferences; draft = preferences.designs[0] }
    func scheduleSave() {
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.flush() }; pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28, execute: item)
    }
    func flush() {
        pending?.cancel(); pending = nil
        let design = draft.validated
        guard selected < preferences.designs.count else { return }
        if preferences.designs[selected] != design { preferences.designs[selected] = design }
    }
    func select(_ index: Int) {
        guard index >= 0 && index < Int(preferences.count.rounded()), index != selected else { return }
        flush(); selected = index; draft = preferences.designs[index]; history = []; future = []
    }
    func remember() { history.append(draft); if history.count > 40 { history.removeFirst() }; future = [] }
    func undo() { guard let previous = history.popLast() else { return }; future.append(draft); draft = previous; flush() }
    func redo() { guard let next = future.popLast() else { return }; history.append(draft); draft = next; flush() }
    func reset() { remember(); draft = FishDesign.initial(selected); flush() }
    func clearPattern() { remember(); draft.variant = -1; draft.strokes = []; flush() }
    func setBody(_ value: UInt32) { remember(); draft.bodyColor = value; flush() }
    func setFin(_ value: UInt32) { remember(); draft.finColor = value; flush() }
}

final class FishDrawingView: NSView {
    var state: FishEditorState
    var activeStroke: Int?
    var cursorPoint: CGPoint?
    init(state: FishEditorState) { self.state = state; super.init(frame: .zero); wantsLayer = true }
    required init?(coder: NSCoder) { fatalError() }
    override var acceptsFirstResponder: Bool { true }
    var drawingScale: CGFloat { min(bounds.width / 142, bounds.height / 96) * 0.76 * pow(state.draft.size, 0.25) }
    var origin: CGPoint { CGPoint(x: bounds.midX + drawingScale * 16, y: bounds.midY) }
    func fishPoint(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        return CGPoint(x: (p.x - origin.x) / drawingScale, y: (p.y - origin.y) / drawingScale)
    }
    override func updateTrackingAreas() {
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow], owner: self, userInfo: nil))
        super.updateTrackingAreas()
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setFillColor(color(0x1C352D).cgColor); ctx.fill(bounds)
        ctx.setStrokeColor(color(0x547466, 0.13).cgColor); ctx.setLineWidth(0.5)
        let spacing: CGFloat = 28
        for x in stride(from: CGFloat(0), to: bounds.width, by: spacing) { ctx.move(to: CGPoint(x: x, y: 0)); ctx.addLine(to: CGPoint(x: x, y: bounds.height)) }
        for y in stride(from: CGFloat(0), to: bounds.height, by: spacing) { ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: bounds.width, y: y)) }
        ctx.strokePath()
        ctx.saveGState(); ctx.translateBy(x: origin.x, y: origin.y); ctx.scaleBy(x: drawingScale, y: drawingScale)
        ctx.setLineCap(.round); ctx.setLineJoin(.round)
        FishPainter.drawWhole(ctx, design: state.draft)
        if let point = cursorPoint {
            ctx.setStrokeColor(color(0xF3E8D4, 0.9).cgColor); ctx.setLineWidth(1 / drawingScale)
            let width = state.brushWidth
            ctx.strokeEllipse(in: CGRect(x: point.x - width / 2, y: point.y - width / 2, width: width, height: width))
        }
        ctx.restoreGState()
    }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let p = fishPoint(event)
        guard fishBodyPath().contains(p) else { return }
        guard state.draft.strokes.count < 240 else { state.notice = "笔画已满，可以先撤销或清空花纹。"; return }
        state.remember()
        activeStroke = state.draft.strokes.count
        state.draft.strokes.append(PaintStroke(points: [PaintPoint(x: p.x, y: p.y)], color: state.brushColor, width: state.brushWidth, erases: state.eraser))
        cursorPoint = p; needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        guard let index = activeStroke, index < state.draft.strokes.count else { return }
        let p = fishPoint(event)
        guard let last = state.draft.strokes[index].points.last, hypot(p.x - last.x, p.y - last.y) > 0.25, state.draft.strokes[index].points.count < 1200 else { return }
        state.draft.strokes[index].points.append(PaintPoint(x: p.x, y: p.y)); cursorPoint = p; needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) { activeStroke = nil; state.flush(); needsDisplay = true }
    override func mouseMoved(with event: NSEvent) { cursorPoint = fishPoint(event); needsDisplay = true }
    override func mouseExited(with event: NSEvent) { cursorPoint = nil; needsDisplay = true }
    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "z" {
            if event.modifierFlags.contains(.shift) { state.redo() } else { state.undo() }
            needsDisplay = true
        } else { super.keyDown(with: event) }
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
}
struct FishPaintCanvas: NSViewRepresentable {
    @ObservedObject var state: FishEditorState
    func makeNSView(context: Context) -> FishDrawingView { FishDrawingView(state: state) }
    func updateNSView(_ view: FishDrawingView, context: Context) { view.needsDisplay = true }
}

struct SolidColorControl: View {
    let title: String
    @Binding var selection: UInt32
    @State private var expanded = false
    @State private var hex = ""
    @State private var invalid = false
    let choices: [(String, UInt32)] = [
        ("瓷白", 0xF1E8D2), ("暖白", 0xDBD3B8), ("银灰", 0xA9B9AF), ("乌金", 0x29342C),
        ("赤金", 0xD97436), ("朱砂", 0xB84A32), ("胭脂", 0x943D43), ("珊瑚", 0xDE8E7A),
        ("琥珀", 0xC79E43), ("浅金", 0xE6C574), ("杏黄", 0xE6A26A), ("麦黄", 0xBAA46A),
        ("荷绿", 0x547A4A), ("青玉", 0x7FA68D), ("湖蓝", 0x5D8F9B), ("靛青", 0x3F627D),
        ("莲紫", 0x997FA0), ("藕粉", 0xD4ADB3), ("棕褐", 0x795C42), ("墨灰", 0x56635C)
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                Spacer()
                Button { expanded.toggle(); hex = String(format: "%06X", selection); invalid = false } label: {
                    HStack(spacing: 7) {
                        RoundedRectangle(cornerRadius: 4).fill(Color(nsColor: color(selection))).frame(width: 34, height: 23)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(nsColor: color(0xA8B6A1)), lineWidth: 0.7))
                        Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.system(size: 9))
                    }
                }.buttonStyle(.plain).accessibilityLabel("选择" + title)
            }
            if expanded {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 4), spacing: 7) {
                    ForEach(choices, id: \.0) { label, hex in
                        Button { selection = hex; expanded = false } label: {
                            VStack(spacing: 4) {
                                RoundedRectangle(cornerRadius: 4).fill(Color(nsColor: color(hex))).frame(height: 24)
                                Text(label).font(.system(size: 9))
                            }
                        }.buttonStyle(.plain).accessibilityLabel(title + "：" + label)
                    }
                }
                HStack(spacing: 5) {
                    Text("色号 #").font(.system(size: 10))
                    TextField("RRGGBB", text: $hex).textFieldStyle(.roundedBorder).font(.system(size: 11, design: .monospaced)).onSubmit(applyHex)
                    Button("应用", action: applyHex).controlSize(.small)
                }
                if invalid { Text("请输入六位色号，例如 D97436。").font(.system(size: 10)).foregroundStyle(Color(nsColor: color(0xE4A69A))) }
            }
        }.onChange(of: selection) { value in hex = String(format: "%06X", value) }
    }
    func applyHex() {
        let text = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        if text.count == 6, let value = UInt32(text, radix: 16) { selection = value; invalid = false; expanded = false }
        else { invalid = true }
    }
}

struct FishEditorContent: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var state: FishEditorState
    var done: () -> Void
    let ink = Color(nsColor: color(0xECE8D4)), muted = Color(nsColor: color(0xA6B5A4))
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                Text("池中金鱼").font(.custom("STSongti-SC-Regular", size: 24)).foregroundStyle(ink)
                Text("为每一尾，添点不同。").font(.system(size: 10)).foregroundStyle(muted)
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(0..<Int(preferences.count.rounded()), id: \.self) { index in
                            Button { state.select(index) } label: {
                                HStack(spacing: 9) {
                                    Circle().fill(Color(nsColor: color(preferences.designs[index].bodyColor))).frame(width: 13, height: 13)
                                    Text(preferences.designs[index].name).font(.system(size: 12)).lineLimit(1)
                                    Spacer()
                                    if state.selected == index { Image(systemName: "pencil.tip").font(.system(size: 11)) }
                                }.padding(10).foregroundStyle(ink)
                                    .background(state.selected == index ? Color(nsColor: color(0x49604A)) : .clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }.buttonStyle(.plain)
                        }
                    }
                }
                Text("\(Int(preferences.count)) 尾 · 单独保存外观").font(.system(size: 10)).foregroundStyle(muted)
            }.padding(20).frame(width: 180).background(Color(nsColor: color(0x243D31)))
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("金鱼画室").font(.custom("STSongti-SC-Regular", size: 31))
                        Text("在鱼身上拖动画笔，让花纹自由生长。").font(.system(size: 12)).foregroundStyle(muted)
                    }
                    Spacer()
                    Button { state.undo() } label: { Image(systemName: "arrow.uturn.backward") }.disabled(state.history.isEmpty).help("撤销 · ⌘Z")
                    Button { state.redo() } label: { Image(systemName: "arrow.uturn.forward") }.disabled(state.future.isEmpty).help("重做 · ⇧⌘Z")
                }.padding(24)
                FishPaintCanvas(state: state).clipShape(RoundedRectangle(cornerRadius: 8)).padding(.horizontal, 20)
                HStack {
                    Label(state.eraser ? "橡皮擦" : "画笔", systemImage: state.eraser ? "eraser" : "paintbrush.pointed")
                    Text("· 在鱼身上绘制").foregroundStyle(muted)
                    Spacer()
                    Text("\(state.draft.strokes.count) 笔").foregroundStyle(muted)
                }.font(.system(size: 11)).padding(20)
                Text(state.notice).font(.system(size: 11)).foregroundStyle(muted).padding(.horizontal, 20).padding(.bottom, 22)
            }.frame(minWidth: 470).foregroundStyle(ink).background(Color(nsColor: color(0x1B3028)))
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("这尾金鱼").font(.custom("STSongti-SC-Regular", size: 24))
                    TextField("金鱼的名字", text: $state.draft.name).textFieldStyle(.roundedBorder)
                    SolidColorControl(title: "鱼身颜色", selection: Binding(get: { state.draft.bodyColor }, set: { state.setBody($0) }))
                    SolidColorControl(title: "鱼鳍颜色", selection: Binding(get: { state.draft.finColor }, set: { state.setFin($0) }))
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { Text("大小"); Spacer(); Text("\(Int(state.draft.size * 100))%").monospacedDigit().foregroundStyle(muted) }
                        Slider(value: $state.draft.size, in: 0.45...2).tint(Color(nsColor: color(0xBEC696)))
                        Text("45% — 200%，即时同步到池塘。").font(.system(size: 10)).foregroundStyle(muted)
                    }
                    Divider().overlay(Color(nsColor: color(0x48604F)))
                    Text("手绘花纹").font(.system(size: 11, weight: .medium)).tracking(2).foregroundStyle(muted)
                    Picker("工具", selection: $state.eraser) { Text("画笔").tag(false); Text("橡皮").tag(true) }.pickerStyle(.segmented)
                    HStack(spacing: 7) {
                        ForEach([UInt32(0xF5E8CE), 0xE18B40, 0xB84A32, 0x2C3430, 0xD3B454, 0xA5B5AE], id: \.self) { hex in
                            Button { state.brushColor = hex; state.eraser = false } label: {
                                Circle().fill(Color(nsColor: color(hex))).frame(width: 25, height: 25)
                                    .overlay(Circle().stroke(state.brushColor == hex ? ink : .clear, lineWidth: 2)).padding(2)
                            }.buttonStyle(.plain).accessibilityLabel("画笔色 #\(String(format: "%06X", hex))")
                        }
                    }
                    SolidColorControl(title: "画笔颜色", selection: $state.brushColor)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { Text("笔刷粗细"); Spacer(); Text(String(format: "%.1f", state.brushWidth)).foregroundStyle(muted) }
                        Slider(value: $state.brushWidth, in: 0.7...10).tint(Color(nsColor: color(0xBEC696)))
                    }
                    Picker("起始花纹", selection: Binding(get: { state.draft.variant }, set: { state.remember(); state.draft.variant = $0; state.flush() })) {
                        Text("纯色").tag(-1); Text("细鳞原色").tag(0); Text("金色原样").tag(2); Text("橙白斑").tag(1); Text("白色带纹").tag(3)
                    }
                    HStack {
                        Button("清空花纹") { state.clearPattern() }
                        Spacer()
                        Button("恢复原样") { state.reset() }
                    }.controlSize(.small)
                    Button { state.flush(); done() } label: { Label("回到池塘", systemImage: "water.waves").frame(maxWidth: .infinity) }.buttonStyle(.bordered).controlSize(.large)
                }.font(.system(size: 12)).padding(24)
            }.frame(width: 285).background(Color(nsColor: color(0x294333)))
        }.foregroundStyle(ink).preferredColorScheme(.dark)
        .onChange(of: preferences.count) { value in if state.selected >= Int(value.rounded()) { state.select(0) } }
    }
}
