import SwiftUI

@main
struct RoseLinkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var engine = BluetoothEngine()
    @AppStorage("preferredFamily") private var preferredFamilyRaw = ProtocolFamily.auto.rawValue
    @AppStorage("showInMenuBar") private var showInMenuBar = true

    var body: some Scene {
        WindowGroup("RoseLink", id: "main") {
            RootView()
                .environmentObject(engine)
                .frame(minWidth: 760, minHeight: 520)
                .onAppear { applyPreferredFamily() }
                .onChange(of: preferredFamilyRaw) { _ in applyPreferredFamily() }
        }
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(replacing: .newItem) {}

            CommandMenu("设备") {
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
    }

    private func setNoise(_ mode: NoiseMode) {
        let cmd = CommandSet.profile(for: engine.activeFamily)
        engine.send(cmd.noiseMode(mode), note: mode.title)
    }

    private func applyPreferredFamily() {
        let family = ProtocolFamily(rawValue: preferredFamilyRaw) ?? .auto
        engine.preferredFamily = family
    }
}
