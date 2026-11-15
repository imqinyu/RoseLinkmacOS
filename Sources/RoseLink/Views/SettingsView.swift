import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var engine: BluetoothEngine

    @AppStorage("preferredFamily") private var preferredFamilyRaw = ProtocolFamily.auto.rawValue
    @AppStorage("showInMenuBar") private var showInMenuBar = true
    @AppStorage("autoConnectOnLaunch") private var autoConnectOnLaunch = true
    @AppStorage("autoReconnectOnSystemConnect") private var autoReconnectOnSystemConnect = true
    @AppStorage("alwaysHideWindow") private var alwaysHideWindow = true
    @AppStorage("menuBarBatterySource") private var menuBarBatterySource = BatterySource.highest.rawValue
    @AppStorage("menuBarShowsBattery") private var menuBarBatteryShowsValue = true

    /// 从 bundle 读取，避免版本号在两处各写一遍后走样。
    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }

    var body: some View {
        TabView {
            Form {
                Section {
                    Picker("默认协议族", selection: $preferredFamilyRaw) {
                        ForEach(ProtocolFamily.allCases) { family in
                            Text(family.displayName).tag(family.rawValue)
                        }
                    }
                    .onChange(of: preferredFamilyRaw) { newValue in
                        engine.preferredFamily = ProtocolFamily(rawValue: newValue) ?? .auto
                    }
                } header: {
                    Text("连接")
                } footer: {
                    Text("「自动识别」按设备名匹配型号。若识别错误，可在此手动指定。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Toggle("启动时自动连接上次的设备", isOn: $autoConnectOnLaunch)

                    Toggle("始终隐藏主窗口", isOn: $alwaysHideWindow)

                    Toggle("耳机重新连上时自动恢复控制", isOn: $autoReconnectOnSystemConnect)
                } header: {
                    Text("连接与启动")
                } footer: {
                    Text("监听到系统蓝牙重新建立连接时，自动打开上次设备的控制通道，无需手动点连接。在 App 内主动点「断开」后不会自动重连。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Toggle("在菜单栏显示控制项", isOn: $showInMenuBar)

                    Toggle("图标旁显示电量", isOn: $menuBarBatteryShowsValue)
                        .disabled(!showInMenuBar)

                    Picker("电量来源", selection: $menuBarBatterySource) {
                        ForEach(BatterySource.allCases) { source in
                            Text(source.title).tag(source.rawValue)
                        }
                    }
                    .disabled(!showInMenuBar || !menuBarBatteryShowsValue)
                } header: {
                    Text("菜单栏")
                } footer: {
                    Text("「最高 / 最低 / 平均值」只统计左右耳——耳机仓收纳时通常上报 0，混入会把平均值拉低。要看仓电量请单独选择。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("通用", systemImage: "gearshape") }

            Form {
                Section("关于") {
                    LabeledContent("名称") { Text("RoseLink for macOS") }
                    LabeledContent("版本") { Text(appVersion) }
                    LabeledContent("数据来源") { Text("RoseLink 3.8.5 APK") }
                }

                Section {
                    Text("协议帧格式与指令表由 Android 版本的 Flutter AOT 快照逆向还原，并经真机抓包逐字节校验。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("说明")
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("关于", systemImage: "info.circle") }
        }
        .frame(width: 460, height: 340)
    }
}
