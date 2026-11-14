import SwiftUI

struct SettingsView: View {
    @AppStorage("preferredFamily") private var preferredFamilyRaw = ProtocolFamily.auto.rawValue
    @AppStorage("showInMenuBar") private var showInMenuBar = true
    @AppStorage("autoConnectOnLaunch") private var autoConnectOnLaunch = true

    var body: some View {
        TabView {
            Form {
                Section {
                    Picker("默认协议族", selection: $preferredFamilyRaw) {
                        ForEach(ProtocolFamily.allCases) { family in
                            Text(family.displayName).tag(family.rawValue)
                        }
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
                } header: {
                    Text("启动")
                } footer: {
                    Text("关闭后，应用启动只列出设备，需要手动连接。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Toggle("在菜单栏显示控制项", isOn: $showInMenuBar)
                } header: {
                    Text("菜单栏")
                } footer: {
                    Text("打开后可直接从菜单栏查看电量并切换降噪模式，无需切回主窗口。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("通用", systemImage: "gearshape") }

            Form {
                Section("关于") {
                    LabeledContent("名称") { Text("RoseLink for macOS") }
                    LabeledContent("版本") { Text("1.1") }
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
