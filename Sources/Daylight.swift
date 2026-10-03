import AppKit

func blend(_ a: UInt32, _ b: UInt32, _ t: Double) -> UInt32 {
    guard t > 0 else { return a }
    func channel(_ shift: Int) -> UInt32 {
        let av = Double((a >> shift) & 255), bv = Double((b >> shift) & 255)
        return UInt32((av + (bv - av) * min(1, max(0, t))).rounded())
    }
    return channel(16) << 16 | channel(8) << 8 | channel(0)
}

// 一天的四个时段光色：中午保持主题原色，其余时段把池水、池底、植物、金鱼与
// 水面反光一起推向对应光色。全部是纯色烘焙与节点染色，不使用渐变；时段进入
// 池底缓存签名，边界处一次重建。“自动”按本地时钟切换，也可在设置里固定。
struct Daylight {
    let key: String, name: String
    let tint: UInt32          // 推向的时段色
    let strength: Double      // 时段色强度
    let dim: Double           // 向深池色压暗的比例
    let glow: UInt32          // 水面反光的光色
    let glowAlpha: Double     // 反光亮度倍率
    let glintBlend: CGFloat   // 反光节点的染色比例

    static let dawn = Daylight(key: "dawn", name: "凌晨", tint: 0x4A5A80, strength: 0.30, dim: 0.18, glow: 0xD6DFF0, glowAlpha: 0.6, glintBlend: 0.45)
    static let noon = Daylight(key: "noon", name: "中午", tint: 0x385E50, strength: 0, dim: 0, glow: 0xFFF6D8, glowAlpha: 1, glintBlend: 0)
    static let dusk = Daylight(key: "dusk", name: "傍晚", tint: 0x9A6238, strength: 0.26, dim: 0.16, glow: 0xFFC97E, glowAlpha: 1.15, glintBlend: 0.55)
    static let night = Daylight(key: "night", name: "晚上", tint: 0x14304A, strength: 0.42, dim: 0.34, glow: 0xAFC6E8, glowAlpha: 0.5, glintBlend: 0.5)

    static let all: [String: Daylight] = ["dawn": .dawn, "noon": .noon, "dusk": .dusk, "night": .night]

    // 自动档：4–10 点凌晨，11–16 点中午，17–19 点傍晚，其余为晚上。
    static func effective(mode: String, date: Date = Date()) -> Daylight {
        if mode != "auto", let fixed = all[mode] { return fixed }
        switch Calendar.current.component(.hour, from: date) {
        case 4..<11: return .dawn
        case 11..<17: return .noon
        case 17..<20: return .dusk
        default: return .night
        }
    }

    // 先压暗再上时段色；烘焙与染色共用同一份光色，保证整体一致。
    func apply(_ hex: UInt32) -> UInt32 { blend(blend(hex, 0x0A1712, dim), tint, strength) }
    var plantBlend: CGFloat { CGFloat(strength * 0.6) }
    var fishBlend: CGFloat { CGFloat(strength * 0.42) }
}
