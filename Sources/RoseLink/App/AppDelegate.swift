import AppKit

/// 在主窗口与「纯菜单栏工具」两种形态之间切换。
///
/// - 主窗口可见时：`.regular`，Dock 有图标、有应用菜单栏
/// - 主窗口全部关闭后：`.accessory`，Dock 图标和应用菜单一起收起，
///   但 `MenuBarExtra` 的状态项仍然保留
///
/// 启动行为：
/// - 首次运行会打开主窗口，让用户确认软件确实跑起来了
/// - 之后启动只驻留菜单栏；打开「始终隐藏主窗口」后连首次也不弹
final class AppDelegate: NSObject, NSApplicationDelegate {

    private enum Keys {
        static let hasLaunchedBefore = "hasLaunchedBefore"
        static let alwaysHideWindow = "alwaysHideWindow"
    }

    /// 默认只在菜单栏驻留，不弹主窗口。需要窗口的用户可在设置里关掉此项。
    override init() {
        UserDefaults.standard.register(defaults: [Keys.alwaysHideWindow: true])
        super.init()
    }

    /// 本次启动是否要抑制主窗口。只在启动阶段短暂为 true。
    private var pendingHiddenStart = false

    private var startsHidden: Bool {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: Keys.alwaysHideWindow) { return true }
        return defaults.bool(forKey: Keys.hasLaunchedBefore)
    }

    // MARK: 生命周期

    func applicationWillFinishLaunching(_ notification: Notification) {
        // 先降级成菜单栏 App，避免登录项启动时窗口抢焦点。
        if startsHidden {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
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
        pendingHiddenStart = startsHidden
        UserDefaults.standard.set(true, forKey: Keys.hasLaunchedBefore)

        if pendingHiddenStart {
            // SwiftUI 建窗口的时机比 didFinishLaunching 稍晚，分两次尝试，
            // 每次都只在「还没关过」的情况下动手。
            closeStartupWindow(after: 0.05)
            closeStartupWindow(after: 0.35)
            // 兜底：始终没等到窗口就撤回标记，避免之后用户手动打开的窗口被误关。
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.pendingHiddenStart = false
            }
        }
    }

    /// 启动即隐藏时，把 SwiftUI 已经建出来的主窗口关掉（此时窗口被隐藏，用户看不到闪动）。
    private func closeStartupWindow(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.pendingHiddenStart else { return }
            let windows = NSApp.windows.filter { Self.isUserWindow($0) }
            guard !windows.isEmpty else { return }
            self.pendingHiddenStart = false
            windows.forEach { $0.close() }
        }
    }

    /// 最后一个窗口关掉后继续驻留菜单栏，不退出。
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
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

    /// 从菜单栏唤回主窗口前调用。
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
