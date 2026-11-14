import AppKit
import SwiftUI

/// SF Symbols 里「左右分明的耳机」图标是较新系统才有的，
/// 老系统上必须降级，否则会渲染成空白占位。
enum SystemSymbol {

    /// 返回第一个在当前系统里真实存在的符号名。
    static func first(of names: [String]) -> String? {
        for name in names where NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil {
            return name
        }
        return nil
    }

    // 优先用 AirPods Pro 系列的左右耳分体图标（SF Symbols 5 / macOS 14 起提供），
    // 老系统依次退回通用耳机图标。
    static let earbudLeft: String? = first(of: [
        "airpods.pro.left", "earbuds.stemless.left", "earbud.left",
    ])
    static let earbudRight: String? = first(of: [
        "airpods.pro.right", "earbuds.stemless.right", "earbud.right",
    ])
    static let chargingCase: String = first(of: [
        "airpods.pro.chargingcase.wireless", "earbuds.case", "airpods.gen3",
    ]) ?? "airpods"
    static let disconnect: String =
        first(of: ["antenna.radiowaves.left.and.right.slash"]) ?? "antenna.radiowaves.left.and.right"
}

enum BatteryTarget {
    case left, right, chargingCase

    var symbol: String {
        switch self {
        case .left: return SystemSymbol.earbudLeft ?? "earbuds"
        case .right: return SystemSymbol.earbudRight ?? "earbuds"
        case .chargingCase: return SystemSymbol.chargingCase
        }
    }

    var shortLabel: String {
        switch self {
        case .left: return "左"
        case .right: return "右"
        case .chargingCase: return "仓"
        }
    }

    var accessibilityName: String {
        switch self {
        case .left: return "左耳"
        case .right: return "右耳"
        case .chargingCase: return "充电仓"
        }
    }

    /// 左右耳图标只是互为镜像，在菜单栏这个字号下肉眼看不出差别，
    /// 所以始终保留一个字的标签；充电仓的图标形态独立，不需要文字。
    var needsTextLabel: Bool {
        switch self {
        case .left, .right: return true
        case .chargingCase: return false
        }
    }
}

/// 单侧电量标签，主窗口与菜单栏面板共用。
struct BatteryIndicator: View {
    let target: BatteryTarget
    let value: Int?

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: target.symbol)
                .font(.caption2)
                .foregroundStyle(.secondary)

            if target.needsTextLabel {
                Text(target.shortLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(value.map { "\($0)%" } ?? "—")
                .font(.caption.weight(.medium))
                .monospacedDigit()
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(target.accessibilityName)电量 \(value.map { "\($0)%" } ?? "未知")")
    }
}
