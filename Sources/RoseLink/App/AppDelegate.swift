import AppKit
import Combine
import SwiftUI

private enum Keys {
    static let hasLaunchedBefore = "hasLaunchedBefore"
    static let alwaysHideWindow = "alwaysHideWindow"
}

/// 菜单栏优先的 App 控制器。
///
/// 主窗口**不在 SwiftUI 场景图里**，而是按需创建 `NSWindow`。
/// 这是刻意的：如果把它交给 `WindowGroup`，SwiftUI 会在启动时创建并显示它，
/// 我们只能事后关掉——无论如何都会闪一帧以上。自建窗口则在启动路径上
/// 根本不存在，用户看不到任何闪现。
final class AppDelegate: NSObject, NSApplicationDelegate {

    /// 引擎由 delegate 持有，界面通过 `environmentObject` 取用。
    let engine = BluetoothEngine()

    /// `@NSApplicationDelegateAdaptor` 会把我们的 delegate 挂成 SwiftUI 内部代理的子代理，
    /// 所以 `NSApp.delegate as? AppDelegate` 永远是 nil。这里自己留一个引用。
    private(set) static weak var shared: AppDelegate?

    private var mainWindow: NSWindow?
    private var titleCancellable: AnyCancellable?

    /// 默认只在菜单栏驻留，不弹主窗口。需要窗口的用户可在设置里关掉此项。
    override init() {
        UserDefaults.standard.register(defaults: [Keys.alwaysHideWindow: true])
        super.init()
        Self.shared = self
    }

    /// 本次启动是否不显示主窗口。
    static var startsHiddenAtLaunch: Bool {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: Keys.alwaysHideWindow) { return true }
        return defaults.bool(forKey: Keys.hasLaunchedBefore)
    }

    // MARK: 生命周期

    func applicationWillFinishLaunching(_ notification: Notification) {
        if Self.startsHiddenAtLaunch {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 必须在写入 hasLaunchedBefore 之前求值，否则第二次启动起永远读到 true。
        let hiddenAtLaunch = Self.startsHiddenAtLaunch

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )

        UserDefaults.standard.set(true, forKey: Keys.hasLaunchedBefore)

        // 自建窗口不会自动继承 navigationTitle，这里手动跟随连接状态更新标题。
        titleCancellable = engine.$phase.sink { [weak self] phase in
            self?.mainWindow?.title = phase.deviceName ?? "RoseLink"
        }

        // 协议族偏好要在自动连接之前生效。
        if let raw = UserDefaults.standard.string(forKey: "preferredFamily"),
           let family = ProtocolFamily(rawValue: raw) {
            engine.preferredFamily = family
        }

        // 连接不再依赖窗口是否打开：开机自启时也能自动连上耳机。
        engine.restoreLastConnection()

        if !hiddenAtLaunch {
            showMainWindow()
        }
    }

    /// 最后一个窗口关掉后继续驻留菜单栏，不退出。
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: 主窗口

    @objc func showMainWindow() {
        Self.restoreDockIcon()

        if mainWindow == nil {
            let hosting = NSHostingController(
                rootView: RootView().environmentObject(engine)
            )
            let window = NSWindow(contentViewController: hosting)
            window.title = engine.phase.deviceName ?? "RoseLink"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 900, height: 572))
            window.minSize = NSSize(width: 760, height: 520)
            window.isReleasedWhenClosed = false
            window.center()
            mainWindow = window
        }

        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: 窗口通知

    @objc private func windowWillClose(_ note: Notification) {
        guard let window = note.object as? NSWindow, Self.isUserWindow(window) else { return }
        // 等这一轮 runloop 收尾，窗口才真正从可见列表里消失。
        DispatchQueue.main.async {
            let stillVisible = NSApp.windows.contains {
                Self.isUserWindow($0) && $0.isVisible
            }
            if !stillVisible {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    @objc private func windowDidBecomeKey(_ note: Notification) {
        guard let window = note.object as? NSWindow, Self.isUserWindow(window) else { return }
        Self.restoreDockIcon()
    }

    // MARK: 辅助

    /// 从菜单栏唤回主窗口前调用：恢复 Dock 图标。
    static func restoreDockIcon() {
        if NSApp.activationPolicy() != .regular {
            NSApp.setActivationPolicy(.regular)
        }
    }

    /// 排除菜单栏面板（NSPanel）之类的辅助窗口，避免误判。
    private static func isUserWindow(_ window: NSWindow) -> Bool {
        window.styleMask.contains(.titled) && !(window is NSPanel) && window.canBecomeMain
    }
}
