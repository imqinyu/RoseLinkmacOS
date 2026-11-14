import SwiftUI

struct DeviceDetailView: View {
    @EnvironmentObject private var engine: BluetoothEngine
    @AppStorage("preferredFamily") private var preferredFamilyRaw = ProtocolFamily.auto.rawValue

    @State private var noiseMode: NoiseMode = .normal
    @State private var extraMode: NoiseMode = .wind
    @State private var ancLevel: Double = 5
    @State private var transparencyLevel: Double = 5
    @State private var eqPreset: EQPreset = .hifi
    @State private var codec: AudioCodec = .sbcAac
    @State private var gameMode = false
    @State private var dualDevice = false
    @State private var earDetection = true
    @State private var touchControl = true
    @State private var tapControl = true
    @State private var spatialOn = false
    @State private var spatialMode: SpatialMode = .off
    @State private var spatialMedia: SpatialMediaMode = .music
    @State private var headMovement = false
    @State private var language: InterfaceLanguage = .chinese
    @State private var dingLevel: Double = 2
    @State private var showInspector = false

    private var commands: CommandSet { CommandSet.profile(for: engine.activeFamily) }

    private var deviceName: String {
        if case .ready(let name) = engine.phase { return name }
        return "耳机"
    }

    var body: some View {
        Form {
            overviewSection
            noiseSection
            audioSection
            spatialSection
            deviceSection
            findSection
            advancedSection
        }
        .formStyle(.grouped)
        .navigationTitle(deviceName)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showInspector = true
                } label: {
                    Label("数据帧", systemImage: "waveform.path")
                }
                .help("查看收发的原始 BLE 数据帧")
            }
        }
        .sheet(isPresented: $showInspector) {
            FrameInspectorView()
                .environmentObject(engine)
        }
        .onAppear(perform: syncFromDevice)
        .onChange(of: engine.state.noiseMode) { newValue in
            if let newValue { noiseMode = primaryMode(for: newValue) ?? newValue; extraMode = newValue }
        }
        .onChange(of: engine.state.ancLevel) { newValue in if let newValue { ancLevel = Double(newValue) } }
        .onChange(of: engine.state.transparencyLevel) { newValue in
            if let newValue { transparencyLevel = Double(newValue) }
        }
        .onChange(of: engine.state.eq) { newValue in if let newValue { eqPreset = newValue } }
        .onChange(of: engine.state.gameMode) { newValue in if let newValue { gameMode = newValue } }
        .onChange(of: engine.state.dualDevice) { newValue in if let newValue { dualDevice = newValue } }
        .onChange(of: engine.state.earDetection) { newValue in if let newValue { earDetection = newValue } }
        .onChange(of: engine.state.touchControl) { newValue in if let newValue { touchControl = newValue } }
        .onChange(of: engine.state.spatialMediaMode) { newValue in if let newValue { spatialMedia = newValue } }
        .onChange(of: engine.state.codec) { newValue in if let newValue { codec = newValue } }
    }

    // MARK: 概览

    @ViewBuilder
    private var overviewSection: some View {
        Section {
            HStack(alignment: .center, spacing: 18) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("电量")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(engine.state.battery.map { "\($0)%" } ?? "—")
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                .frame(width: 110, alignment: .leading)

                VStack(alignment: .leading, spacing: 8) {
                    Gauge(value: Double(engine.state.battery ?? 0), in: 0...100) {
                        EmptyView()
                    } currentValueLabel: {
                        EmptyView()
                    }
                    .gaugeStyle(.accessoryLinearCapacity)
                    .tint(batteryTint)
                    .accessibilityLabel("剩余电量")
                    .accessibilityValue(engine.state.battery.map { "\($0)%" } ?? "未知")

                    HStack(spacing: 14) {
                        BatteryIndicator(target: .left, value: engine.state.batteryLeft)
                        BatteryIndicator(target: .right, value: engine.state.batteryRight)
                        if let batteryCase = engine.state.batteryCase {
                            BatteryIndicator(target: .chargingCase, value: batteryCase)
                        }
                    }

                    // 耳机仓出仓后不再上报，标注数据新鲜度，避免误以为是实时值。
                    if let updatedAt = engine.state.batteryCaseUpdatedAt {
                        TimelineView(.periodic(from: .now, by: 30)) { _ in
                            Text(BatteryFreshness.caseBatteryDescription(for: updatedAt))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.vertical, 6)

            LabeledContent("协议族") {
                Text(engine.activeFamily.displayName)
            }
            if let firmware = engine.state.firmware {
                LabeledContent("固件版本") { Text(firmware) }
            }
        } header: {
            Label("概览", systemImage: "dot.radiowaves.left.and.right")
        }
    }

    private var batteryTint: Color {
        guard let battery = engine.state.battery else { return .secondary }
        switch battery {
        case 0...15: return .red
        case 16...35: return .orange
        default: return .green
        }
    }

    // MARK: 噪声控制

    @ViewBuilder
    private var noiseSection: some View {
        Section {
            Picker("模式", selection: $noiseMode) {
                ForEach([NoiseMode.anc, .transparency, .normal], id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: noiseMode) { newValue in
                applyNoise(newValue)
            }

            Picker("更多模式", selection: $extraMode) {
                ForEach(extraModes, id: \.self) { mode in
                    Label(mode.title, systemImage: mode.symbol).tag(mode)
                }
            }
            .onChange(of: extraMode) { newValue in
                applyNoise(newValue)
            }

            LabeledContent("降噪强度") {
                HStack(spacing: 10) {
                    Slider(value: $ancLevel, in: 1...10, step: 1) { editing in
                        if !editing { engine.send(commands.ancLevel(Int(ancLevel)), note: "降噪强度") }
                    }
                    .frame(width: 160)
                    Text("\(Int(ancLevel))")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 22, alignment: .trailing)
                }
            }
            .disabled(engine.activeFamily == .f8 || engine.activeFamily == .zt)

            LabeledContent("通透强度") {
                HStack(spacing: 10) {
                    Slider(value: $transparencyLevel, in: 1...10, step: 1) { editing in
                        if !editing {
                            engine.send(commands.transparencyLevel(Int(transparencyLevel)), note: "通透强度")
                        }
                    }
                    .frame(width: 160)
                    Text("\(Int(transparencyLevel))")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 22, alignment: .trailing)
                }
            }
            .disabled(engine.activeFamily == .f8 || engine.activeFamily == .zt)
        } header: {
            Label("噪声控制", systemImage: "waveform.badge.minus")
        } footer: {
            if !engine.activeFamily.isVerified {
                Text("当前协议族的帧封装尚未逐字节验证，指令可能不会生效。可在「高级」中切换协议族。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var extraModes: [NoiseMode] {
        switch engine.activeFamily {
        case .zt:
            return [.wind, .adaptive]
        case .f8:
            return [.wind]
        default:
            return [.wind, .adaptive, .deepANC, .adaptiveDynamic]
        }
    }

    private func primaryMode(for mode: NoiseMode) -> NoiseMode? {
        switch mode {
        case .anc, .deepANC, .adaptive, .adaptiveDynamic: return .anc
        case .transparency: return .transparency
        case .normal: return .normal
        case .wind: return nil
        }
    }

    private func applyNoise(_ mode: NoiseMode) {
        engine.send(commands.noiseMode(mode), note: mode.title)
    }

    // MARK: 音效

    @ViewBuilder
    private var audioSection: some View {
        Section {
            Picker("均衡器", selection: $eqPreset) {
                ForEach(EQPreset.allCases.filter { isSupported($0) }, id: \.self) { preset in
                    Text(preset.title).tag(preset)
                }
            }
            .onChange(of: eqPreset) { newValue in
                engine.send(commands.eq(newValue), note: "均衡器：\(newValue.title)")
            }

            if engine.activeFamily != .zt {
                Picker("音频编码", selection: $codec) {
                    ForEach(AudioCodec.allCases.filter { isSupported($0) }, id: \.self) { value in
                        Text(value.title).tag(value)
                    }
                }
                .onChange(of: codec) { newValue in
                    engine.send(commands.codec(newValue), note: "编码：\(newValue.title)")
                }
            }

            Toggle("游戏模式", isOn: $gameMode)
                .onChange(of: gameMode) { newValue in
                    engine.send(commands.gameMode(newValue), note: "游戏模式")
                }
        } header: {
            Label("音效", systemImage: "slider.horizontal.3")
        }
    }

    private func isSupported(_ preset: EQPreset) -> Bool {
        commands.eq(preset) != nil
    }

    private func isSupported(_ codec: AudioCodec) -> Bool {
        commands.codec(codec) != nil
    }

    // MARK: 空间音频

    @ViewBuilder
    private var spatialSection: some View {
        Section {
            Toggle("空间音频", isOn: $spatialOn)
                .onChange(of: spatialOn) { newValue in
                    engine.send(commands.spatialSwitch(newValue), note: "空间音频")
                }
                .disabled(commands.spatialSwitch(true) == nil)

            Picker("定位方式", selection: $spatialMode) {
                ForEach(SpatialMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .onChange(of: spatialMode) { newValue in
                engine.send(commands.spatialMode(newValue), note: "空间音频：\(newValue.title)")
            }
            .disabled(commands.spatialMode(.fixed) == nil)

            Picker("内容类型", selection: $spatialMedia) {
                ForEach(SpatialMediaMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .onChange(of: spatialMedia) { newValue in
                engine.send(commands.spatialMediaMode(newValue), note: "空间音频内容：\(newValue.title)")
            }
            .disabled(commands.spatialMediaMode(.game) == nil)

            Toggle("头部动作识别", isOn: $headMovement)
                .onChange(of: headMovement) { newValue in
                    engine.send(commands.headMovementMode(newValue), note: "头部动作")
                }
                .disabled(commands.headMovementMode(true) == nil)
        } header: {
            Label("空间音频", systemImage: "circle.hexagongrid")
        }
    }

    // MARK: 设备

    @ViewBuilder
    private var deviceSection: some View {
        Section {
            Toggle("双设备连接", isOn: $dualDevice)
                .onChange(of: dualDevice) { newValue in
                    engine.send(commands.dualDevice(newValue), note: "双设备连接")
                }
                .disabled(commands.dualDevice(true) == nil)

            Toggle("入耳检测", isOn: $earDetection)
                .onChange(of: earDetection) { newValue in
                    engine.send(commands.earDetection(newValue), note: "入耳检测")
                }
                .disabled(commands.earDetection(true) == nil)

            Toggle("触控操作", isOn: $touchControl)
                .onChange(of: touchControl) { newValue in
                    engine.send(commands.touchControl(newValue), note: "触控操作")
                }
                .disabled(commands.touchControl(true) == nil)

            Toggle("双击 / 三击手势", isOn: $tapControl)
                .onChange(of: tapControl) { newValue in
                    engine.send(commands.tapControl(newValue), note: "手势")
                }
                .disabled(commands.tapControl(true) == nil)

            Picker("语音提示语言", selection: $language) {
                ForEach(InterfaceLanguage.allCases, id: \.self) { value in
                    Text(value.title).tag(value)
                }
            }
            .onChange(of: language) { newValue in
                engine.send(commands.interfaceLanguage(newValue), note: "提示语言")
            }
            .disabled(commands.interfaceLanguage(.english) == nil)

            LabeledContent("提示音音量") {
                HStack(spacing: 10) {
                    Slider(value: $dingLevel, in: 1...5, step: 1) { editing in
                        if !editing { engine.send(commands.dingLevel(Int(dingLevel)), note: "提示音音量") }
                    }
                    .frame(width: 160)
                    Text("\(Int(dingLevel))")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 22, alignment: .trailing)
                }
            }
            .disabled(commands.dingLevel(1) == nil)
        } header: {
            Label("设备行为", systemImage: "airpods.gen3")
        }
    }

    // MARK: 查找

    @ViewBuilder
    private var findSection: some View {
        Section {
            HStack(spacing: 10) {
                ForEach(FindTarget.allCases) { target in
                    Button {
                        engine.send(commands.findDevice(target), note: "查找 \(target.title)")
                    } label: {
                        Label(target.title, systemImage: "speaker.wave.2")
                            .frame(maxWidth: .infinity)
                    }
                }
                Button("停止") {
                    engine.send(commands.findDevice(nil), note: "停止查找")
                }
                .frame(maxWidth: 90)
            }
            .disabled(commands.findDevice(.both) == nil)
        } header: {
            Label("查找耳机", systemImage: "location.magnifyingglass")
        } footer: {
            Text("耳机会播放提示音，帮助你在附近定位。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: 高级

    @ViewBuilder
    private var advancedSection: some View {
        Section {
            Picker("协议族", selection: $preferredFamilyRaw) {
                ForEach(ProtocolFamily.allCases) { family in
                    Text(family.displayName).tag(family.rawValue)
                }
            }

            HStack {
                Button("重新读取状态") {
                    engine.send(commands.pollAll(), note: "查询设备状态")
                }
                Spacer()
                Button("查看数据帧") { showInspector = true }
            }
        } header: {
            Label("高级", systemImage: "gearshape.2")
        } footer: {
            Text("协议族与指令表由 RoseLink 3.8.5 逆向还原。若设备无响应，请尝试切换协议族。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func syncFromDevice() {
        if let mode = engine.state.noiseMode {
            noiseMode = primaryMode(for: mode) ?? noiseMode
            extraMode = mode
        }
        if let level = engine.state.ancLevel { ancLevel = Double(level) }
        if let level = engine.state.transparencyLevel { transparencyLevel = Double(level) }
        if let preset = engine.state.eq { eqPreset = preset }
        if let value = engine.state.codec { codec = value }
        if let value = engine.state.gameMode { gameMode = value }
        if let value = engine.state.dualDevice { dualDevice = value }
        if let value = engine.state.earDetection { earDetection = value }
        if let value = engine.state.touchControl { touchControl = value }
        if let value = engine.state.spatialMediaMode { spatialMedia = value }
        if let value = engine.state.interfaceLanguage { language = value }
        if let value = engine.state.dingLevel { dingLevel = Double(value) }
    }
}


