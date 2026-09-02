import AppKit

// A programmatic AppKit app: no storyboard, so the whole UI is readable Swift
// and the package builds and runs straight from Xcode.
let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.regular)
application.run()
