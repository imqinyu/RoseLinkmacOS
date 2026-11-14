import CoreBluetooth
import Foundation

/// ROSESELSA / RoseLink 家族的 BLE 协议族。
///
/// 逆向自 RoseLink 3.8.5（Flutter AOT，`package:roselink_bluetooth`）。
/// 各族的帧封装：
/// - `.rsCommon`   : `FF <payload> AA`（无序号、无校验）
/// - `.rsCommonV2` : `FF <seq> <payload> <sum> AA`
/// - `.f8`         : 原始 payload（自带嵌套 LTV，无外层封装）
/// - `.zt`         : `08 EE <payload> <sum>`，当前按原样下发
enum ProtocolFamily: String, CaseIterable, Identifiable, Codable {
    case auto
    case rsCommon
    case rsCommonV2
    case f8
    case zt

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return "自动识别"
        case .rsCommon: return "RS-Common（初代）"
        case .rsCommonV2: return "RS-Common V2"
        case .f8: return "F8 平台"
        case .zt: return "ZT 平台"
        }
    }

    var shortName: String {
        switch self {
        case .auto: return "自动"
        case .rsCommon: return "V1"
        case .rsCommonV2: return "V2"
        case .f8: return "F8"
        case .zt: return "ZT"
        }
    }

    /// 该协议族是否为逐字节验证过的实现。
    var isVerified: Bool {
        self == .rsCommon || self == .rsCommonV2
    }
}

// MARK: - 功能枚举

enum NoiseMode: String, CaseIterable, Identifiable {
    case anc, transparency, normal, wind, adaptive, deepANC, adaptiveDynamic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .anc: return "主动降噪"
        case .transparency: return "通透模式"
        case .normal: return "普通"
        case .wind: return "抗风噪"
        case .adaptive: return "自适应降噪"
        case .deepANC: return "深度降噪"
        case .adaptiveDynamic: return "动态自适应"
        }
    }

    var symbol: String {
        switch self {
        case .anc, .deepANC, .adaptive, .adaptiveDynamic: return "waveform.badge.minus"
        case .transparency: return "waveform"
        case .normal: return "speaker.slash"
        case .wind: return "wind"
        }
    }
}

enum EQPreset: String, CaseIterable, Identifiable {
    case hifi, pop, rock, light, custom, bassBoost, eap
    case game1, game2, game3, game4, game5

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hifi: return "HiFi"
        case .pop: return "流行"
        case .rock: return "摇滚"
        case .light: return "轻音乐"
        case .custom: return "自定义"
        case .bassBoost: return "低音增强"
        case .eap: return "EAP"
        case .game1: return "游戏 1"
        case .game2: return "游戏 2"
        case .game3: return "游戏 3"
        case .game4: return "游戏 4"
        case .game5: return "游戏 5"
        }
    }
}

enum AudioCodec: String, CaseIterable, Identifiable {
    case sbcAac, ldac, lhdc, lc3, aptx, aptxHD, aptxAdaptive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sbcAac: return "SBC / AAC"
        case .ldac: return "LDAC"
        case .lhdc: return "LHDC"
        case .lc3: return "LC3"
        case .aptx: return "aptX"
        case .aptxHD: return "aptX HD"
        case .aptxAdaptive: return "aptX Adaptive"
        }
    }
}

enum SpatialMode: String, CaseIterable, Identifiable {
    case off, fixed, headTracking

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "关闭"
        case .fixed: return "固定"
        case .headTracking: return "头部跟踪"
        }
    }
}

enum SpatialMediaMode: String, CaseIterable, Identifiable {
    case tv, music, movie, game

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tv: return "电视"
        case .music: return "音乐"
        case .movie: return "电影"
        case .game: return "游戏"
        }
    }
}

enum InterfaceLanguage: String, CaseIterable, Identifiable {
    case chinese, english

    var id: String { rawValue }
    var title: String { self == .chinese ? "中文" : "English" }
}

/// 菜单栏图标旁显示哪一个电量。
///
/// 聚合项（最高 / 最低 / 平均）只统计左右耳——耳机仓在收纳状态下常上报 0，
/// 混进去会把平均值拉得离谱。
enum BatterySource: String, CaseIterable, Identifiable {
    case highest, lowest, average, left, right, chargingCase

    var id: String { rawValue }

    var title: String {
        switch self {
        case .highest: return "最高电量"
        case .lowest: return "最低电量"
        case .average: return "平均值"
        case .left: return "左耳电量"
        case .right: return "右耳电量"
        case .chargingCase: return "耳机仓电量"
        }
    }

    var isAggregate: Bool {
        self == .highest || self == .lowest || self == .average
    }
}

// MARK: - 设备识别

/// 广播名 → 协议族映射。数据来自 APK 中各 `*_device_config.dart` 的
/// `customConfigEarObject()`（型号名 + 协议标识）。
enum DeviceRegistry {
    private static let table: [(prefix: String, family: ProtocolFamily)] = [
        // F8 平台
        ("CERAMICSX7034", .f8),
        ("CERAMICSX", .f8),
        ("CERAMICS", .f8),
        ("AGATEX", .f8),
        ("AGATE", .f8),
        ("EXPLORER", .f8),

        // ZT 平台
        ("EARFREEI5", .zt),
        ("EARFREEI3", .zt),
        ("HEADFEEL", .zt),

        // RS-Common 初代
        ("ROSEEARFEELIE2", .rsCommonV2),
        ("BUDSSFREEI", .rsCommon),
        ("BUDSFREE", .rsCommon),
        ("CAM BRIAN", .rsCommon),
        ("CAMBRIAN", .rsCommon),
        ("OPENFEEL", .rsCommonV2),
        ("OPENFUN", .rsCommon),
        ("OPENLINK", .rsCommon),
        ("SPORTFEEL", .rsCommonV2),
        ("SPEAKFEEL", .rsCommonV2),
        ("SPEAKFREE", .rsCommonV2),

        // RS-Common V2
        ("SWIFT2", .rsCommonV2),
        ("SWIFT", .rsCommon),
        ("ASTROX", .rsCommonV2),
        ("ZIRCON", .rsCommonV2),
        ("OPAL", .rsCommonV2),
        ("CORAL", .rsCommonV2),
        ("HYACINTH", .rsCommonV2),
        ("JASMINE", .rsCommonV2),
        ("MOKA", .rsCommonV2),
        ("MIRROR", .rsCommonV2),
        ("FURINA", .rsCommonV2),
        ("AURAMIC", .rsCommonV2),
        ("FIRSTANGEL", .rsCommonV2),
        ("CERAMICSUHSC2710", .rsCommonV2),
        ("CERAMICSU", .rsCommonV2),
        ("CERAMICSMK28912F", .rsCommonV2),
        ("CERAMICSMK25736", .rsCommonV2),
        ("CERAMICSMK2", .rsCommonV2),
        ("BUDSFEELMK2", .rsCommonV2),
        ("BUDSFEELAENEO", .rsCommonV2),
        ("EARFEELI7", .rsCommonV2),
        ("EARFEELIENEO", .rsCommonV2),
        ("KY01", .rsCommonV2),
        ("LUMINOUS", .rsCommonV2),
        ("OPENFEELMK2", .rsCommonV2),
        ("OPENFEEL", .rsCommonV2),
    ]

    /// 归一化广播名：去掉空格与连接符，统一大写。
    static func normalize(_ name: String) -> String {
        name.uppercased().filter { $0.isLetter || $0.isNumber }
    }

    /// 按最长前缀匹配，避免 `CERAMICS-X` 误匹配到 `CERAMICS`。
    ///
    /// 实测广播名常带品牌前缀（如 `ROSE Ceramics MK2`），所以先按原样匹配，
    /// 失败再去掉品牌前缀重试。
    static func family(for advertisedName: String?) -> ProtocolFamily? {
        guard let name = advertisedName else { return nil }
        let key = normalize(name)
        guard !key.isEmpty else { return nil }
        if let matched = match(key) { return matched }

        for brand in ["ROSESELSA", "ROSELINK", "ROSLINK", "ROSE"] where key.hasPrefix(brand) {
            if let matched = match(String(key.dropFirst(brand.count))) { return matched }
        }
        return nil
    }

    private static func match(_ key: String) -> ProtocolFamily? {
        guard !key.isEmpty else { return nil }
        return table
            .filter { key.hasPrefix($0.prefix) }
            .max { $0.prefix.count < $1.prefix.count }?
            .family
    }

    /// ROSESELSA 设备的广播名特征，用于过滤无关 BLE 设备。
    static func looksLikeRoseDevice(_ name: String?) -> Bool {
        guard let name, !name.isEmpty else { return false }
        if family(for: name) != nil { return true }
        let key = normalize(name)
        return ["ROSE", "ROSESELSA", "ROSLINK", "ROSELINK"].contains { key.hasPrefix($0) }
    }
}
