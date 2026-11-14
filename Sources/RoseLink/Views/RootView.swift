import SwiftUI

struct RootView: View {
    @EnvironmentObject private var engine: BluetoothEngine
    @State private var selection: String?

    var body: some View {
        NavigationSplitView {
            DeviceSidebar(selection: $selection)
                .navigationSplitViewColumnWidth(min: 250, ideal: 270, max: 340)
        } detail: {
            if engine.phase.isReady {
                DeviceDetailView()
            } else {
                ConnectionPlaceholder()
            }
        }
        .onAppear {
            // 列出已配对设备，并在开启自动重连时恢复上一次的连接。
            engine.restoreLastConnection()
        }
        .toolbar {
            ToolbarItem(placement: .status) {
                ConnectionStatusPill(phase: engine.phase)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    engine.startScan()
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .help("重新扫描并刷新已配对设备（⌘R）")
                .disabled(engine.phase.isReady)
            }
        }
    }
}

// MARK: - 侧边栏

private struct DeviceSidebar: View {
    @EnvironmentObject private var engine: BluetoothEngine
    @Binding var selection: String?

    private var classicDevices: [DiscoveredDevice] {
        engine.devices.filter { $0.transport == .rfcomm }
    }

    private var bleDevices: [DiscoveredDevice] {
        engine.devices.filter { $0.transport == .ble }
    }

    private var selectedDevice: DiscoveredDevice? {
        guard let selection else { return nil }
        return engine.devices.first { $0.id == selection }
    }

    var body: some View {
        List(selection: $selection) {
            Section {
                if classicDevices.isEmpty {
                    Text("未找到已配对的耳机\n请先在「系统设置 › 蓝牙」中配对")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    ForEach(classicDevices) { device in
                        row(for: device)
                    }
                }
            } header: {
                Text("已配对")
            }

            if !bleDevices.isEmpty {
                Section("附近（低功耗）") {
                    ForEach(bleDevices) { device in
                        row(for: device)
                    }
                }
            }

            if engine.phase.isReady {
                Section("连接信息") {
                    LabeledContent("通道") {
                        Text(engine.activeTransport.title)
                    }
                    LabeledContent("协议") {
                        Text(engine.activeFamily.displayName)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            if !engine.phase.isReady {
                VStack(spacing: 8) {
                    Button {
                        if let selectedDevice { connect(selectedDevice) }
                    } label: {
                        Label("连接", systemImage: "link")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(selectedDevice == nil)

                    Button {
                        engine.startScan()
                    } label: {
                        Label("重新搜索", systemImage: "dot.radiowaves.left.and.right")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                }
                .padding(12)
            }
        }
    }

    /// `List` 会吞掉普通 tap 手势，必须同时用 `contentShape` 铺满命中区域、
    /// 并用 `simultaneousGesture` 才能稳定收到双击。
    private func row(for device: DiscoveredDevice) -> some View {
        DeviceRow(device: device)
            .tag(device.id)
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture(count: 2).onEnded { connect(device) })
            .contextMenu {
                Button("连接") { connect(device) }
            }
    }

    private func connect(_ device: DiscoveredDevice) {
        selection = device.id
        engine.connect(device)
    }
}

private struct DeviceRow: View {
    let device: DiscoveredDevice

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "airpodspro")
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.displayName)
                    .lineLimit(1)
                Text(device.family?.shortName ?? "未知协议")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            if let rssi = device.rssi {
                SignalStrength(rssi: rssi)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(device.displayName)，\(device.transport.title)\(device.rssi.map { "，信号 \($0) dBm" } ?? "")"
        )
    }
}

private struct SignalStrength: View {
    let rssi: Int

    private var bars: Double {
        switch rssi {
        case (-55)...: return 1.0
        case (-75)..<(-55): return 0.66
        default: return 0.33
        }
    }

    var body: some View {
        Image(systemName: "wifi", variableValue: bars)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.secondary)
            .help("信号强度 \(rssi) dBm")
    }
}

struct ConnectionStatusPill: View {
    let phase: ConnectionPhase

    private var tint: Color {
        switch phase {
        case .ready: return .green
        case .failed, .poweredOff, .unauthorized: return .red
        case .scanning, .connecting, .discovering: return .orange
        case .idle: return .secondary
        }
    }

    private var title: String {
        switch phase {
        case .ready: return "已连接"
        case .failed: return "连接异常"
        case .poweredOff: return "蓝牙关闭"
        case .unauthorized: return "未授权"
        case .scanning: return "搜索中"
        case .connecting: return "连接中"
        case .discovering: return "建立通道"
        case .idle: return "未连接"
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .help(phase.summary)
    }
}

// MARK: - 空状态

private struct ConnectionPlaceholder: View {
    @EnvironmentObject private var engine: BluetoothEngine

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "airpodspro")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(.tertiary)
                .symbolRenderingMode(.hierarchical)

            Text(engine.phase.summary)
                .font(.title3)

            Text("在左侧选中一副耳机，点「连接」或直接双击。\n控制通道走经典蓝牙，请确保耳机已在系统设置中配对。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if case .failed(let reason) = engine.phase {
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .underPageBackgroundColor))
    }
}
