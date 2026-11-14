import AppKit

/// 在主窗口与「纯菜单栏工具」两种形态之间切换。
///
/// - 主窗口可见时：`.regular`，Dock 有图标、有应用菜单栏
/// - 主窗口全部关闭后：`.accessory`，Dock 图标和应用菜单一起收起，
///   但 `MenuBarExtra` 的状态项仍然保留
///
/// 这样关窗不会退出应用，也不会在 Dock 里留下一个空壳图标。
final class AppDelegate: NSObject, NSApplicationDelegate {

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
    }

    /// 最后一个窗口关掉后继续驻留菜单栏，不退出。
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

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
