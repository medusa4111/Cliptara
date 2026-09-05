import AppKit
import Carbon.HIToolbox
import CoreGraphics
import ScreenCaptureKit

enum WindowSelectionControllerError: LocalizedError {
    case noWindowsAvailable

    var errorDescription: String? {
        switch self {
        case .noWindowsAvailable:
            return Localizer.text(
                "Не найдено окон, доступных для скриншота.",
                "No windows are available for capture."
            )
        }
    }
}

@MainActor
final class WindowSelectionController {
    private struct Candidate {
        let windowID: CGWindowID
        let frame: CGRect
    }

    private var candidates: [Candidate] = []
    private var overlayPanels: [WindowSelectionPanel] = []
    private var selectionContinuation: CheckedContinuation<CGWindowID?, Never>?
    private var localKeyMonitor: Any?
    private var globalKeyMonitor: Any?
    private var highlightedWindowID: CGWindowID?

    private(set) var isSelecting = false

    func selectWindow() async throws -> CGWindowID? {
        guard !isSelecting else {
            return nil
        }

        isSelecting = true
        do {
            let shareableContent = try await SCShareableContent.current
            let availableCandidates = makeCandidates(from: shareableContent)
            guard !availableCandidates.isEmpty else {
                isSelecting = false
                throw WindowSelectionControllerError.noWindowsAvailable
            }

            candidates = availableCandidates
            return await withCheckedContinuation { continuation in
                selectionContinuation = continuation
                showOverlays()
            }
        } catch {
            isSelecting = false
            throw error
        }
    }

    private func makeCandidates(from content: SCShareableContent) -> [Candidate] {
        let currentProcessID = ProcessInfo.processInfo.processIdentifier
        var shareableWindows: [CGWindowID: SCWindow] = [:]

        for window in content.windows where window.isOnScreen {
            guard window.windowLayer == 0,
                  window.owningApplication?.processID != currentProcessID,
                  window.frame.width >= 80,
                  window.frame.height >= 50 else {
                continue
            }
            shareableWindows[window.windowID] = window
        }

        guard let windowInfo = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return shareableWindows.values.map {
                Candidate(windowID: $0.windowID, frame: $0.frame)
            }
        }

        var result: [Candidate] = []
        for info in windowInfo {
            guard let number = info[kCGWindowNumber as String] as? NSNumber else {
                continue
            }

            let windowID = CGWindowID(number.uint32Value)
            guard let window = shareableWindows.removeValue(forKey: windowID) else {
                continue
            }

            if let alpha = info[kCGWindowAlpha as String] as? NSNumber,
               alpha.doubleValue <= 0 {
                continue
            }

            result.append(Candidate(windowID: window.windowID, frame: window.frame))
        }

        return result
    }

    private func showOverlays() {
        for screen in NSScreen.screens {
            let panel = WindowSelectionPanel(screen: screen)
            let overlayView = WindowSelectionOverlayView(frame: NSRect(origin: .zero, size: screen.frame.size))

            overlayView.onMouseMoved = { [weak self] point in
                self?.updateHighlightedWindow(at: point)
            }
            overlayView.onSelection = { [weak self] point in
                self?.selectWindow(at: point)
            }
            overlayView.onCancel = { [weak self] in
                self?.finishSelection(with: nil)
            }

            panel.contentView = overlayView
            overlayPanels.append(panel)
            panel.orderFrontRegardless()
        }

        overlayPanels.first?.makeKey()
        installEscapeMonitors()
        updateHighlightedWindow(at: NSEvent.mouseLocation)
    }

    private func installEscapeMonitors() {
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == UInt16(kVK_Escape) else {
                return event
            }
            self?.finishSelection(with: nil)
            return nil
        }

        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == UInt16(kVK_Escape) else {
                return
            }
            Task { @MainActor in
                self?.finishSelection(with: nil)
            }
        }
    }

    private func updateHighlightedWindow(at appKitPoint: CGPoint) {
        let candidate = candidate(at: appKitPoint)
        guard candidate?.windowID != highlightedWindowID else {
            return
        }

        highlightedWindowID = candidate?.windowID
        let appKitFrame = candidate.map { appKitRect(fromQuartzRect: $0.frame) }
        for panel in overlayPanels {
            guard let overlay = panel.contentView as? WindowSelectionOverlayView else {
                continue
            }
            overlay.setHighlightedScreenRect(appKitFrame)
        }
    }

    private func selectWindow(at appKitPoint: CGPoint) {
        guard let candidate = candidate(at: appKitPoint) else {
            return
        }
        finishSelection(with: candidate.windowID)
    }

    private func candidate(at appKitPoint: CGPoint) -> Candidate? {
        let quartzPoint = quartzPoint(fromAppKitPoint: appKitPoint)
        return candidates.first { $0.frame.contains(quartzPoint) }
    }

    private func quartzPoint(fromAppKitPoint point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: primaryScreenHeight - point.y)
    }

    private func appKitRect(fromQuartzRect rect: CGRect) -> CGRect {
        CGRect(
            x: rect.minX,
            y: primaryScreenHeight - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    private var primaryScreenHeight: CGFloat {
        NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height
            ?? NSScreen.screens.first?.frame.height
            ?? 0
    }

    private func finishSelection(with windowID: CGWindowID?) {
        guard isSelecting else {
            return
        }

        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }
        if let globalKeyMonitor {
            NSEvent.removeMonitor(globalKeyMonitor)
            self.globalKeyMonitor = nil
        }

        for panel in overlayPanels {
            panel.orderOut(nil)
            panel.close()
        }
        overlayPanels.removeAll()
        candidates.removeAll()
        highlightedWindowID = nil
        isSelecting = false
        NSCursor.arrow.set()

        let continuation = selectionContinuation
        selectionContinuation = nil
        continuation?.resume(returning: windowID)
    }
}

@MainActor
private final class WindowSelectionPanel: NSPanel {
    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    }

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }
}

@MainActor
private final class WindowSelectionOverlayView: NSView {
    var onMouseMoved: ((CGPoint) -> Void)?
    var onSelection: ((CGPoint) -> Void)?
    var onCancel: (() -> Void)?

    private var trackingAreaReference: NSTrackingArea?
    private var highlightedRect: CGRect?

    override var acceptsFirstResponder: Bool {
        true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingAreaReference {
            removeTrackingArea(trackingAreaReference)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        trackingAreaReference = trackingArea
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseEntered(with event: NSEvent) {
        reportMouseLocation(event)
    }

    override func mouseMoved(with event: NSEvent) {
        reportMouseLocation(event)
    }

    override func mouseDragged(with event: NSEvent) {
        reportMouseLocation(event)
    }

    override func mouseDown(with event: NSEvent) {
        guard let point = screenPoint(for: event) else {
            return
        }
        onSelection?(point)
    }

    override func rightMouseDown(with event: NSEvent) {
        onCancel?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) {
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.black.withAlphaComponent(0.08).setFill()
        bounds.fill()

        guard let highlightedRect else {
            return
        }

        let visibleRect = highlightedRect.intersection(bounds).insetBy(dx: 2, dy: 2)
        guard visibleRect.width > 4, visibleRect.height > 4 else {
            return
        }

        let highlightPath = NSBezierPath(roundedRect: visibleRect, xRadius: 10, yRadius: 10)
        NSColor.controlAccentColor.withAlphaComponent(0.18).setFill()
        highlightPath.fill()
        NSColor.controlAccentColor.setStroke()
        highlightPath.lineWidth = 3
        highlightPath.stroke()
    }

    func setHighlightedScreenRect(_ rect: CGRect?) {
        guard let window else {
            highlightedRect = nil
            needsDisplay = true
            return
        }

        highlightedRect = rect.map { window.convertFromScreen($0) }
        needsDisplay = true
    }

    private func reportMouseLocation(_ event: NSEvent) {
        guard let point = screenPoint(for: event) else {
            return
        }
        onMouseMoved?(point)
    }

    private func screenPoint(for event: NSEvent) -> CGPoint? {
        window?.convertPoint(toScreen: event.locationInWindow)
    }
}
