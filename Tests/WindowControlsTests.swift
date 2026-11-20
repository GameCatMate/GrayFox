import AppKit
import SwiftUI

@main struct WindowControlsTests {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 900, height: 500),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.collectionBehavior = .fullScreenPrimary
        window.title = "myBro controls test"
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 900, height: 500))
        let controls = FullscreenWindowButtons.Target(frame: NSRect(x: 0, y: 464, width: 82, height: 36))
        controls.autoresizingMask = .minYMargin
        root.addSubview(controls)
        window.contentView = root
        window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        assert(controls.isHidden && controls.subviews.count == 3)
        window.toggleFullScreen(nil)
        wait { !controls.isHidden && window.styleMask.contains(.fullScreen) }
        let buttons = controls.subviews.compactMap { $0 as? NSButton }
        assert(buttons.count == 3 && buttons.allSatisfy { $0.target === window })
        assert(buttons[0].isEnabled && !buttons[1].isEnabled && buttons[2].isEnabled)
        assert(buttons[0].action == #selector(NSWindow.performClose(_:)))
        assert(buttons[2].action == #selector(NSWindow.toggleFullScreen(_:)))
        assert(buttons.allSatisfy { controls.bounds.contains($0.frame) })
        buttons[2].performClick(nil)
        wait { controls.isHidden && !window.styleMask.contains(.fullScreen) }
        assert(window.standardWindowButton(.closeButton) != nil)
        controls.detach()
        controls.detach()
        window.close()
        print("Native fullscreen controls, layout, exit action and observer cleanup checks passed.")
    }

    @MainActor private static func wait(_ condition: () -> Bool) {
        let end = Date().addingTimeInterval(8)
        while !condition() && Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
        assert(condition(), "Fullscreen transition timed out")
    }
}
