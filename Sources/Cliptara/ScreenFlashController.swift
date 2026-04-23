import AppKit
import Foundation

@MainActor
final class ScreenFlashController {
    static let shared = ScreenFlashController()

    private var windowsByScreenID: [NSNumber: NSWindow] = [:]
    private var isFlashing = false

    private init() {}

    func flash() {
        if isFlashing {
            hideAll()
        }

        syncWindowsWithCurrentScreens()
        guard !windowsByScreenID.isEmpty else {
            return
        }

        isFlashing = true
        for window in windowsByScreenID.values {
            window.alphaValue = 0.72
            window.orderFrontRegardless()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            guard let self else { return }
            self.hideAll()
            self.isFlashing = false
        }
    }

    private func hideAll() {
        for window in windowsByScreenID.values {
            window.alphaValue = 0
            window.orderOut(nil)
        }
    }

    private func syncWindowsWithCurrentScreens() {
        let screens = NSScreen.screens
        let activeIDs = Set(screens.map { NSNumber(value: $0.displayID) })

        for (screenID, window) in windowsByScreenID where !activeIDs.contains(screenID) {
            window.orderOut(nil)
            window.close()
            windowsByScreenID.removeValue(forKey: screenID)
        }

        for screen in screens {
            let screenID = NSNumber(value: screen.displayID)
            if let existing = windowsByScreenID[screenID] {
                existing.setFrame(screen.frame, display: true)
                continue
            }

            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.isOpaque = false
            window.backgroundColor = .white
            window.alphaValue = 0
            window.level = .statusBar
            window.ignoresMouseEvents = true
            window.hasShadow = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

            windowsByScreenID[screenID] = window
        }
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}
