import AppKit
import SwiftUI

/// 菜单栏常驻图标：连接时顺带显示电量。
struct MenuBarLabel: View {
    @ObservedObject var engine: BluetoothEngine
    @AppStorage("menuBarBatterySource") private var sourceRaw = BatterySource.highest.rawValue
    @AppStorage("menuBarShowsBattery") private var showsBattery = true

    private var source: BatterySource {
        BatterySource(rawValue: sourceRaw) ?? .highest
    }

    private var battery: Int? {
        guard engine.phase.isReady else { return nil }
        return engine.state.battery(for: source)
    }

    var body: some View {
        if showsBattery, let battery {
            HStack(spacing: 3) {
                Image(systemName: symbol(for: battery))
                Text("\(battery)%")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
            }
        } else {
            Image(systemName: "airpodspro")
        }
    }

    private func symbol(for battery: Int) -> String {
        battery <= 15 ? "airpodspro.chargingcase.wireless" : "airpodspro"
    }
}

/// 菜单栏下拉面板。保持与主窗口同一套引擎，状态实时同步。
struct MenuBarPanel: View {
    @ObservedObject var engine: BluetoothEngine
    @Environment(\.openWindow) private var openWindow

    @State private var noiseMode: NoiseMode = .normal
    @State private var eqPreset: EQPreset = .hifi
    @State private var gameMode = false

    private var commands: CommandSet { CommandSet.profile(for: engine.activeFamily) }

    private var primaryModes: [NoiseMode] { [.anc, .transparency, .normal] }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if engine.phase.isReady {
                batteryRow
                Divider()
                noiseControls
                quickToggles
            } else {
                Text(engine.phase.summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()
            footer
        }
        .padding(12)
        .frame(width: 300)
        .onAppear(perform: sync)
        .onChange(of: engine.state.noiseMode) { newValue in
            guard let newValue else { return }
            if primaryModes.contains(newValue) { noiseMode = newValue }
        }
        .onChange(of: engine.state.eq) { newValue in if let newValue { eqPreset = newValue } }
        .onChange(of: engine.state.gameMode) { newValue in if let newValue { gameMode = newValue } }
    }

    // MARK: 区块

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "airpodspro")
                .font(.title3)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(engine.phase.deviceName ?? "RoseLink")
                    .font(.headline)
                    .lineLimit(1)
                Text(engine.activeTransport.title + " · " + engine.activeFamily.shortName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            ConnectionStatusPill(phase: engine.phase)
        }
    }

    private var batteryRow: some View {
        HStack(spacing: 6) {
            BatteryIndicator(target: .left, value: engine.state.batteryLeft)
            BatteryIndicator(target: .right, value: engine.state.batteryRight)
            if let batteryCase = engine.state.batteryCase {
                BatteryIndicator(target: .chargingCase, value: batteryCase)
                    .help(
                        engine.state.batteryCaseUpdatedAt
                            .map { BatteryFreshness.caseBatteryDescription(for: $0) }
                            ?? "充电仓电量"
                    )
            }
            Spacer(minLength: 0)
        }
    }

    private var noiseControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("降噪模式", selection: $noiseMode) {
                ForEach(primaryModes, id: \.self) { mode in
                    Text(shortTitle(mode)).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: noiseMode) { newValue in
                engine.send(commands.noiseMode(newValue), note: newValue.title)
            }
        }
    }

    private var quickToggles: some View {
        HStack(spacing: 10) {
            Picker("均衡器", selection: $eqPreset) {
                ForEach(EQPreset.allCases.filter { commands.eq($0) != nil }, id: \.self) { preset in
                    Text(preset.title).tag(preset)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 130)
            .onChange(of: eqPreset) { newValue in
                engine.send(commands.eq(newValue), note: "均衡器：\(newValue.title)")
            }

            Spacer(minLength: 0)

            Toggle("游戏", isOn: $gameMode)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .onChange(of: gameMode) { newValue in
                    engine.send(commands.gameMode(newValue), note: "游戏模式")
                }
                .disabled(commands.gameMode(true) == nil)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                // 先把 Dock 图标和菜单栏恢复成常规 App，否则唤回的窗口拿不到焦点。
                AppDelegate.restoreDockIcon()
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("主窗口", systemImage: "macwindow")
            }

            Spacer(minLength: 0)

            if engine.phase.isReady {
                Button {
                    engine.disconnect()
                } label: {
                    Label("断开", systemImage: SystemSymbol.disconnect)
                }
            } else {
                Button("重新搜索") { engine.startScan() }
            }

            Button {
                NSApp.terminate(nil)
            } label: {
                Label("退出", systemImage: "power")
            }
            .help("退出 RoseLink")
        }
        .controlSize(.small)
    }

    // MARK: 辅助

    private func shortTitle(_ mode: NoiseMode) -> String {
        switch mode {
        case .anc: return "降噪"
        case .transparency: return "通透"
        case .normal: return "普通"
        default: return mode.title
        }
    }

    private func sync() {
        if let mode = engine.state.noiseMode {
            noiseMode = primaryModes.contains(mode) ? mode : .anc
        }
        if let preset = engine.state.eq { eqPreset = preset }
        if let value = engine.state.gameMode { gameMode = value }
    }
}


