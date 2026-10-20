import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: MainWindowController?
    private var formativeIDMatchWindowController: FormativeIDMatchWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        applyIconWhenRunningUnbundled()
        let controller = MainWindowController()
        windowController = controller
        NSApp.mainMenu = Self.makeMenu(newFileTarget: controller, appDelegate: self)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Created lazily on first use, then kept around so choosing the menu
    /// item again just brings the same window forward instead of making a
    /// second one (and losing whatever was already pasted into it).
    @objc func showFormativeIDMatches() {
        let controller = formativeIDMatchWindowController ?? FormativeIDMatchWindowController()
        formativeIDMatchWindowController = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
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

    /// The minimum menu bar a Mac app is expected to have: Quit, a File menu
    /// with New (there is otherwise no way to start a second file without
    /// quitting and reopening), and the edit commands that make the text
    /// fields behave normally.
    static func makeMenu(newFileTarget: MainWindowController, appDelegate: AppDelegate) -> NSMenu {
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

        let fileMenuItem = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        let newItem = NSMenuItem(
            title: "New", action: #selector(MainWindowController.startNewFile), keyEquivalent: "n")
        newItem.target = newFileTarget
        fileMenu.addItem(newItem)
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

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

        let windowMenuItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        let matchesItem = NSMenuItem(
            title: "Formative ID Matches…",
            action: #selector(AppDelegate.showFormativeIDMatches), keyEquivalent: "")
        matchesItem.target = appDelegate
        windowMenu.addItem(matchesItem)
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        return mainMenu
    }
}
