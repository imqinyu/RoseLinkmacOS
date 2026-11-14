import SwiftUI

@main
struct RoseLinkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("showInMenuBar") private var showInMenuBar = true
    @AppStorage("preferredFamily") private var preferredFamilyRaw = ProtocolFamily.auto.rawValue

    private var engine: BluetoothEngine { appDelegate.engine }

    var body: some Scene {
        // 主窗口不在这里——由 AppDelegate 按需创建 NSWindow，
        // 这样启动时窗口根本不存在，不会有任何闪现。
        MenuBarExtra(isInserted: $showInMenuBar) {
            MenuBarPanel(engine: engine)
        } label: {
            MenuBarLabel(engine: engine)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(engine)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}

            CommandMenu("设备") {
                Button("打开主窗口") {
                    AppDelegate.shared?.showMainWindow()
                }
                .keyboardShortcut("0", modifiers: .command)

                Divider()

                Button("重新搜索") {
                    engine.startScan()
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(engine.phase.isReady)

                Button("断开连接") {
                    engine.disconnect()
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .disabled(!engine.phase.isReady)
            }

            CommandMenu("降噪") {
                Button("主动降噪") { setNoise(.anc) }
                    .keyboardShortcut("1", modifiers: .command)
                    .disabled(!engine.phase.isReady)
                Button("通透模式") { setNoise(.transparency) }
                    .keyboardShortcut("2", modifiers: .command)
                    .disabled(!engine.phase.isReady)
                Button("普通模式") { setNoise(.normal) }
                    .keyboardShortcut("3", modifiers: .command)
                    .disabled(!engine.phase.isReady)
            }

            CommandGroup(after: .sidebar) {
                Toggle("在菜单栏显示控制项", isOn: $showInMenuBar)
            }
        }
    }

    private func setNoise(_ mode: NoiseMode) {
        let cmd = CommandSet.profile(for: engine.activeFamily)
        engine.send(cmd.noiseMode(mode), note: mode.title)
    }
}
