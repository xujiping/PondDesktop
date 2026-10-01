import AppKit
import SpriteKit

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
    precondition(abs(scene.foodTarget!.x - scene.worldSize.width * 0.5) < 0.001, "调整视野时投喂位置必须随池塘缩放")
    print("通过：单尾颜色/大小/笔画持久化、鱼身裁切、橡皮底色恢复、撤销重做、鱼群纹理更新、相机缩放和零尺寸窗口保护。")
}
