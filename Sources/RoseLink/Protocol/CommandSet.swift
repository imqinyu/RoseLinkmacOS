import CoreBluetooth
import Foundation

// MARK: - 帧编解码

/// 由真实抓包（Ceramics MK2 / RS-Common V2）逐字节验证的帧结构：
///
/// ```
/// V2 : FF | seq | len | payload...    | sum | AA
/// V1 : FF |       payload...          |      AA
/// F8 :            payload...                      （无外层封装）
/// ZT : 08 | EE |  payload... | sum                （payload 表已含校验）
/// ```
///
/// `len` 是 payload 的字节数；`sum` 从 `FF` 起到 payload 末字节全部相加后取低 8 位。
/// 例：`09 01`（降噪）→ `FF xx 02 09 01 sum AA`。
enum FrameCodec {

    static func encode(payload: [UInt8], family: ProtocolFamily, sequence: UInt8) -> Data {
        switch family {
        case .rsCommonV2:
            var frame: [UInt8] = [0xFF, sequence, UInt8(truncatingIfNeeded: payload.count)] + payload
            frame.append(checksum(frame))
            frame.append(0xAA)
            return Data(frame)

        case .rsCommon:
            return Data([0xFF] + payload + [0xAA])

        case .f8, .zt, .auto:
            return Data(payload)
        }
    }

    static func checksum(_ bytes: [UInt8]) -> UInt8 {
        bytes.reduce(UInt8(0)) { $0 &+ $1 }
    }
}

/// 把通知数据流切成完整帧。RFCOMM/BLE 单包都可能被拆分或粘连，必须做缓冲。
///
/// 入站方向与出站方向格式不同（实测确认）：
/// - 出站：`FF | seq | len | payload… | sum | AA`
/// - 入站：`DD | seq | LTV…            | sum | AA` —— 没有长度字段，
///   只能靠「校验和 + AA 帧尾」来判定帧结束。
struct FrameStream {
    private var buffer: [UInt8] = []
    private let family: ProtocolFamily

    init(family: ProtocolFamily) {
        self.family = family
    }

    mutating func reset() {
        buffer.removeAll(keepingCapacity: true)
    }

    /// 追加数据并返回解析出的帧载荷（已去掉帧头、序号与校验和）。
    mutating func append(_ data: Data) -> [[UInt8]] {
        buffer.append(contentsOf: data)

        guard family == .rsCommonV2 else {
            // 未验证封装方式的协议族：不猜测切帧，整包透传给上层做原始展示。
            let raw = buffer
            buffer.removeAll(keepingCapacity: true)
            return raw.isEmpty ? [] : [raw]
        }

        var frames: [[UInt8]] = []
        while let start = buffer.firstIndex(of: 0xDD) {
            if start > 0 { buffer.removeFirst(start) }
            guard let length = frameLength() else {
                if buffer.count > 512 { buffer.removeAll(keepingCapacity: true) }
                return frames
            }
            frames.append(Array(buffer[2..<(length - 2)]))
            buffer.removeFirst(length)
        }
        return frames
    }

    /// 用校验和定位帧尾，返回整帧长度（含 DD 与 AA）。
    private func frameLength() -> Int? {
        guard buffer.count >= 5 else { return nil }
        let limit = min(buffer.count, 400)
        for tail in 4..<limit where buffer[tail] == 0xAA {
            let sum = buffer[0..<(tail - 1)].reduce(UInt8(0)) { $0 &+ $1 }
            if sum == buffer[tail - 1] {
                return tail + 1
            }
        }
        return nil
    }
}

// MARK: - 指令集

enum FindTarget: String, CaseIterable, Identifiable {
    case left, right, both

    var id: String { rawValue }

    var title: String {
        switch self {
        case .left: return "左耳"
        case .right: return "右耳"
        case .both: return "双耳"
        }
    }
}

/// 每个协议族一套指令表。payload 不含帧头/校验，由 `FrameCodec` 统一封装。
struct CommandSet {
    let family: ProtocolFamily

    static func profile(for family: ProtocolFamily) -> CommandSet {
        CommandSet(family: family)
    }

    // MARK: 噪声控制

    func noiseMode(_ mode: NoiseMode) -> [UInt8]? {
        switch family {
        case .rsCommon, .rsCommonV2:
            let value: UInt8
            switch mode {
            case .anc: value = 0x01
            case .normal: value = 0x02
            case .transparency: value = 0x03
            case .wind: value = 0x04
            case .adaptive: value = 0x05
            case .deepANC: value = 0x06
            case .adaptiveDynamic: value = 0x07
            }
            return [0x09, value]

        case .f8:
            switch mode {
            case .anc: return [0x2C, 0x01, 0x01, 0x01]
            case .transparency: return [0x2C, 0x01, 0x01, 0x02]
            case .normal: return [0x2C, 0x01, 0x01, 0x03]
            case .wind: return [0x2C, 0x01, 0x01]
            default: return nil
            }

        case .zt:
            switch mode {
            case .anc: return [0x08, 0xEE, 0x06, 0x82, 0x0D, 0x01, 0x8C]
            case .transparency: return [0x08, 0xEE, 0x06, 0x82, 0x0D, 0x01, 0x8C]
            case .normal: return [0x08, 0xEE, 0x06, 0x82, 0x0D, 0x01, 0x8C]
            case .wind: return [0x08, 0xEE, 0x06, 0x82, 0x0E, 0x01, 0x8D]
            case .adaptive: return [0x08, 0xEE, 0x06, 0x82, 0x0E, 0x02, 0x8E]
            default: return nil
            }

        case .auto:
            return nil
        }
    }

    func ancLevel(_ value: Int) -> [UInt8]? {
        switch family {
        case .rsCommon, .rsCommonV2: return [0x2C, UInt8(clamping: value)]
        default: return nil
        }
    }

    func transparencyLevel(_ value: Int) -> [UInt8]? {
        switch family {
        case .rsCommon, .rsCommonV2: return [0x2D, UInt8(clamping: value)]
        default: return nil
        }
    }

    func hearingProtection(_ level: Int) -> [UInt8]? {
        switch family {
        case .rsCommon, .rsCommonV2: return [0x46, UInt8(clamping: level)]
        default: return nil
        }
    }

    func gainLevel(_ level: Int) -> [UInt8]? {
        switch family {
        case .rsCommon, .rsCommonV2: return [0x45, UInt8(clamping: level)]
        default: return nil
        }
    }

    func dingLevel(_ level: Int) -> [UInt8]? {
        switch family {
        case .rsCommon, .rsCommonV2: return [0x2E, UInt8(clamping: level)]
        default: return nil
        }
    }

    // MARK: 音效

    func eq(_ preset: EQPreset) -> [UInt8]? {
        switch family {
        case .rsCommon, .rsCommonV2:
            let value: UInt8
            switch preset {
            case .hifi: value = 0x00
            case .pop: value = 0x01
            case .rock: value = 0x02
            case .light: value = 0x03
            case .custom: value = 0x04
            case .bassBoost: value = 0x05
            case .eap: value = 0x06
            case .game1: value = 0xA0
            case .game2: value = 0xA1
            case .game3: value = 0xA2
            case .game4: value = 0xA3
            case .game5: value = 0xA4
            }
            return [0x2A, value]

        case .f8:
            switch preset {
            case .hifi: return [0x20, 0x01, 0x02]
            case .pop: return [0x20, 0x01, 0x02, 0x01]
            case .rock: return [0x20, 0x01, 0x02, 0x02]
            default: return nil
            }

        case .zt:
            switch preset {
            case .hifi: return [0x08, 0xEE, 0x02, 0x81, 0x0B, 0x01, 0x85]
            case .pop: return [0x08, 0xEE, 0x02, 0x81, 0x0B, 0x84]
            case .rock: return [0x08, 0xEE, 0x02, 0x81, 0x0B, 0x02, 0x86]
            case .light: return [0x08, 0xEE, 0x02, 0x81, 0x0B, 0x03, 0x87]
            default: return nil
            }

        case .auto:
            return nil
        }
    }

    func gameMode(_ on: Bool) -> [UInt8]? {
        switch family {
        case .rsCommon, .rsCommonV2: return [0x0E, on ? 0x01 : 0x00]
        case .f8: return [0x25, 0x01, 0x01] + (on ? [0x01] : [])
        case .zt: return on
            ? [0x08, 0xEE, 0x06, 0x83, 0x0B, 0x8A]
            : [0x08, 0xEE, 0x06, 0x83, 0x0B, 0x01, 0x8B]
        case .auto: return nil
        }
    }

    func codec(_ codec: AudioCodec) -> [UInt8]? {
        switch family {
        case .rsCommon, .rsCommonV2:
            let value: UInt8
            switch codec {
            case .sbcAac: value = 0x00
            case .ldac: value = 0x01
            case .lhdc: value = 0x02
            case .lc3: value = 0x03
            case .aptx: value = 0x04
            case .aptxHD: value = 0x05
            case .aptxAdaptive: value = 0x06
            }
            return [0x2B, value]

        case .f8:
            switch codec {
            case .ldac: return [0x2B, 0x01, 0x01, 0x01]
            case .sbcAac: return [0x2B, 0x01, 0x01, 0x02]
            case .lhdc: return [0x2B, 0x01, 0x01, 0x03]
            default: return nil
            }

        case .zt:
            switch codec {
            case .ldac: return [0x08, 0xEE, 0x08, 0x81, 0x0B, 0x01, 0x8B]
            case .lhdc: return [0x08, 0xEE, 0x08, 0x81, 0x0B, 0x02, 0x8C]
            default: return nil
            }

        case .auto:
            return nil
        }
    }

    // MARK: 空间音频

    func spatialSwitch(_ on: Bool) -> [UInt8]? {
        switch family {
        case .rsCommon, .rsCommonV2: return [0x33, on ? 0x01 : 0x00]
        case .zt: return on
            ? [0x08, 0xEE, 0x0B, 0x81, 0x0B, 0x01, 0x8E]
            : [0x08, 0xEE, 0x0B, 0x81, 0x0B, 0x8D]
        default: return nil
        }
    }

    func spatialMode(_ mode: SpatialMode) -> [UInt8]? {
        switch family {
        case .rsCommon, .rsCommonV2:
            switch mode {
            case .off: return [0x38, 0x00]
            case .headTracking: return [0x38, 0x01]
            case .fixed: return [0x38, 0x02]
            }
        default:
            return nil
        }
    }

    func spatialMediaMode(_ mode: SpatialMediaMode) -> [UInt8]? {
        switch family {
        case .rsCommon, .rsCommonV2:
            switch mode {
            case .tv: return [0x3D, 0x00]
            case .music: return [0x3D, 0x01]
            case .movie: return [0x3D, 0x02]
            case .game: return [0x3D, 0x03]
            }
        default:
            return nil
        }
    }

    func headMovementMode(_ on: Bool) -> [UInt8]? {
        switch family {
        case .rsCommon, .rsCommonV2: return [0x39, on ? 0x01 : 0x00]
        default: return nil
        }
    }

    // MARK: 设备行为

    func earDetection(_ on: Bool) -> [UInt8]? {
        switch family {
        case .rsCommon, .rsCommonV2: return on ? [0x08] : [0x08, 0x01]
        case .f8: return [0x26, 0x01, 0x01] + (on ? [0x01] : [])
        case .zt: return on
            ? [0x08, 0xEE, 0x0C, 0x81, 0x0B, 0x8E]
            : [0x08, 0xEE, 0x0C, 0x81, 0x0B, 0x01, 0x8F]
        case .auto: return nil
        }
    }

    func touchControl(_ on: Bool) -> [UInt8]? {
        switch family {
        case .rsCommon, .rsCommonV2: return on ? [0x07] : [0x07, 0x01]
        case .f8: return [0x33, 0x01, 0x01] + (on ? [0x01] : [])
        case .zt: return on
            ? [0x08, 0xEE, 0x0A, 0x81, 0x0B, 0x8C]
            : [0x08, 0xEE, 0x0A, 0x81, 0x0B, 0x01, 0x8D]
        case .auto: return nil
        }
    }

    func tapControl(_ on: Bool) -> [UInt8]? {
        switch family {
        case .rsCommon, .rsCommonV2: return on ? [0x3B, 0x01] : [0x3B, 0x00]
        default: return nil
        }
    }

    func dualDevice(_ on: Bool) -> [UInt8]? {
        switch family {
        case .rsCommon, .rsCommonV2: return [0x32, on ? 0x01 : 0x00]
        case .f8: return on ? [0x2B, 0x01, 0x01] : nil
        case .zt: return on
            ? [0x08, 0xEE, 0x08, 0x82, 0x0B, 0x01, 0x8C]
            : [0x08, 0xEE, 0x08, 0x82, 0x0B, 0x8B]
        case .auto: return nil
        }
    }

    func interfaceLanguage(_ language: InterfaceLanguage) -> [UInt8]? {
        switch family {
        case .rsCommon, .rsCommonV2: return [0x31, language == .english ? 0x01 : 0x00]
        case .f8: return [0x29, 0x01, 0x01] + (language == .english ? [0x01] : [])
        case .zt: return language == .english
            ? [0x08, 0xEE, 0x0D, 0x81, 0x0B, 0x01, 0x90]
            : [0x08, 0xEE, 0x0D, 0x81, 0x0B, 0x8F]
        case .auto: return nil
        }
    }

    func findDevice(_ target: FindTarget?) -> [UInt8]? {
        switch family {
        case .rsCommon, .rsCommonV2:
            let value: UInt8
            switch target {
            case .left: value = 0x01
            case .right: value = 0x02
            case .both: value = 0x03
            case nil: value = 0x04    // 停止寻找
            }
            return [0x2F, value]
        case .zt:
            return target == nil
                ? [0x08, 0xEE, 0x0B, 0x81, 0x0B, 0x8D]
                : [0x08, 0xEE, 0x0B, 0x81, 0x0B, 0x01, 0x8E]
        default:
            return nil
        }
    }

    func independentMic(_ on: Bool) -> [UInt8]? {
        switch family {
        case .rsCommon, .rsCommonV2: return on ? [0x49, 0x01, 0x01] : [0x49, 0x01]
        default: return nil
        }
    }

    func groupMode(_ on: Bool) -> [UInt8]? {
        switch family {
        case .rsCommon, .rsCommonV2: return [0x4A, on ? 0x01 : 0x00]
        default: return nil
        }
    }

    // MARK: 状态轮询

    /// 连上后主动查询一次设备状态。这一条是从真实抓包里原样抄下来的。
    func pollAll() -> [UInt8]? {
        switch family {
        case .rsCommon, .rsCommonV2:
            return [
                0xFA, 0x0D, 0x0C, 0x09, 0x2C, 0x2D, 0x2A, 0x0E,
                0x32, 0x2B, 0x2F, 0x01, 0x07, 0x31, 0x2E, 0x36,
            ]
        case .f8:
            return [0x27, 0x01, 0x01, 0x01]
        case .zt:
            return [0x08, 0xEE, 0x01, 0x01, 0x0A, 0x02]
        case .auto:
            return nil
        }
    }

    func queryBattery() -> [UInt8]? {
        switch family {
        case .rsCommon, .rsCommonV2: return [0xFA, 0x0C]
        case .f8: return [0x27, 0x01, 0x01, 0x01]
        case .zt: return [0x08, 0xEE, 0x01, 0x03, 0x0A, 0x04]
        case .auto: return nil
        }
    }
}
