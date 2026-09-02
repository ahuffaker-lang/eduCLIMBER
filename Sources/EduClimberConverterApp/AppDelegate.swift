import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: MainWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = Self.makeMenu()
        applyIconWhenRunningUnbundled()
        let controller = MainWindowController()
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        windowController = controller
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// A packaged .app takes its icon from Info.plist. Run straight from Xcode
    /// there is no bundle to read, so point the Dock at the icon in the repo.
    private func applyIconWhenRunningUnbundled() {
        guard Bundle.main.infoDictionary?["CFBundleIconFile"] == nil else { return }
        let sourceRoot = URL(fileURLWithPath: #filePath)  // Sources/<target>/AppDelegate.swift
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let candidates = [
            Bundle.main.bundleURL.appendingPathComponent("AppIcon.icns"),
            sourceRoot.appendingPathComponent("Resources/AppIcon.icns"),
        ]
        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            if let icon = NSImage(contentsOf: url) {
                NSApp.applicationIconImage = icon
                return
            }
        }
    }

    /// The minimum menu bar a Mac app is expected to have: Quit, and the edit
    /// commands that make the text fields behave normally.
    static func makeMenu() -> NSMenu {
        let appName = ProcessInfo.processInfo.processName
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(
            withTitle: "About \(appName)",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Hide \(appName)",
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(
            withTitle: "Quit \(appName)",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(
            withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(
            withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(
            withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(
            withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        return mainMenu
    }
}
