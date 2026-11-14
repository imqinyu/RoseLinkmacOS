import SwiftUI

/// 原始帧检查器。逆向得到的协议仍需在真机上校准，这里可以手动下发任意 payload。
struct FrameInspectorView: View {
    @EnvironmentObject private var engine: BluetoothEngine
    @Environment(\.dismiss) private var dismiss

    @State private var manualHex = "09 01"

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            logList
            Divider()
            composer
        }
        .frame(minWidth: 620, idealWidth: 720, minHeight: 460, idealHeight: 560)
    }

    private var header: some View {
        HStack {
            Text("数据帧")
                .font(.headline)
            Text(engine.activeFamily.displayName)
                .font(.caption)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(.quaternary, in: Capsule())
            Spacer()
            Button("清空") { engine.clearLog() }
            Button("完成") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(12)
    }

    private var logList: some View {
        ScrollViewReader { proxy in
            List(engine.log.reversed()) { entry in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: entry.direction == .outbound ? "arrow.up.right" : "arrow.down.left")
                        .font(.caption2)
                        .foregroundStyle(entry.direction == .outbound ? Color.accentColor : .green)
                        .frame(width: 14)

                    Text(entry.hex)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)

                    if let note = entry.note {
                        Text(note)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)

                    Text(entry.date, format: .dateTime.hour().minute().second())
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
                .id(entry.id)
            }
            .listStyle(.inset)
            .onChange(of: engine.log.count) { _ in
                if let first = engine.log.last {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(first.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("手动下发（十六进制 payload，不含帧头与校验）")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                TextField("09 01", text: $manualHex)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))

                Button("发送") {
                    if let bytes = Self.parseHex(manualHex), !bytes.isEmpty {
                        engine.send(bytes, note: "手动下发")
                    }
                }
                .keyboardShortcut(.return, modifiers: [.command])
            }

            if !engine.activeFamily.isVerified {
                Label("该协议族未逐字节验证，手动下发可用来试探真实帧格式。", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(12)
    }

    static func parseHex(_ text: String) -> [UInt8]? {
        let cleaned = text
            .replacingOccurrences(of: "0x", with: "", options: .caseInsensitive)
            .components(separatedBy: CharacterSet(charactersIn: " ,\n\t"))
            .filter { !$0.isEmpty }

        var bytes: [UInt8] = []
        for token in cleaned {
            // 支持 "0901" 这种连写形式
            if token.count > 2, token.count.isMultiple(of: 2) {
                var index = token.startIndex
                while index < token.endIndex {
                    let next = token.index(index, offsetBy: 2)
                    guard let byte = UInt8(token[index..<next], radix: 16) else { return nil }
                    bytes.append(byte)
                    index = next
                }
            } else {
                guard let byte = UInt8(token, radix: 16) else { return nil }
                bytes.append(byte)
            }
        }
        return bytes
    }
}
