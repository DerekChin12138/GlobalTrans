import AppKit
import CoreGraphics

@MainActor
final class RegionOverlayController {
    private var windows: [NSWindow] = []
    private var continuation: CheckedContinuation<CGRect?, Never>?

    func selectRegion() async -> CGRect? {
        let rect = await withCheckedContinuation { continuation in
            self.continuation = continuation
            present()
        }
        // Never close() or nil the contentView. That SIGSEGVs when AppKit
        // drains the mouse-up autorelease pool. Shrink and orderOut instead.
        await hideWindows()
        return rect
    }

    private func present() {
        let screens = NSScreen.screens
        while windows.count < screens.count {
            windows.append(makeWindow())
        }
        for (index, screen) in screens.enumerated() {
            let window = windows[index]
            if let view = window.contentView as? SelectionView {
                view.reset()
                view.frame = NSRect(origin: .zero, size: screen.frame.size)
            }
            window.backgroundColor = NSColor.black.withAlphaComponent(0.18)
            window.setFrame(screen.frame, display: false)
            window.ignoresMouseEvents = false
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func finish(_ rect: CGRect?) {
        for window in windows {
            window.orderOut(nil)
            window.ignoresMouseEvents = true
        }
        continuation?.resume(returning: rect)
        continuation = nil
    }

    private func hideWindows() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    continuation.resume()
                    return
                }
                for window in self.windows {
                    window.orderOut(nil)
                    window.ignoresMouseEvents = true
                    window.backgroundColor = .clear
                    if let view = window.contentView as? SelectionView {
                        view.reset()
                        view.layer?.contents = nil
                        view.layer?.backgroundColor = nil
                        view.wantsLayer = false
                        view.frame = NSRect(origin: .zero, size: Self.parkedFrame.size)
                    }
                    window.setFrame(Self.parkedFrame, display: false)
                }
                continuation.resume()
            }
        }
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 2, height: 2),
            styleMask: [.borderless],
            backing: .buffered,
            defer: true
        )
        window.identifier = NSUserInterfaceItemIdentifier("GTRegionOverlay")
        window.title = "GTRegionOverlay"
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.isRestorable = false
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentView = SelectionView(frame: .zero) { [weak self] rect in
            self?.finish(rect)
        } onCancel: { [weak self] in
            self?.finish(nil)
        }
        return window
    }

    private static let parkedFrame = NSRect(x: -64, y: -64, width: 2, height: 2)
}

private final class SelectionView: NSView {
    private let onComplete: (CGRect) -> Void
    private let onCancel: () -> Void
    private var start: NSPoint?
    private var current: NSPoint?

    init(frame: NSRect, onComplete: @escaping (CGRect) -> Void, onCancel: @escaping () -> Void) {
        self.onComplete = onComplete
        self.onCancel = onCancel
        super.init(frame: frame)
        wantsLayer = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func reset() {
        start = nil
        current = nil
        needsDisplay = true
    }

    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { false }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel()
        }
    }

    override func mouseDown(with event: NSEvent) {
        start = event.locationInWindow
        current = start
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        current = event.locationInWindow
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        current = event.locationInWindow
        guard let start, let current else {
            onCancel()
            return
        }
        let local = NSRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
        guard local.width >= 8, local.height >= 8, let window else {
            onCancel()
            return
        }
        let screenRect = window.convertToScreen(local)
        onComplete(screenRect)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let start, let current else { return }
        let rect = NSRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
        NSColor.systemTeal.setStroke()
        let path = NSBezierPath(rect: rect)
        path.lineWidth = 2
        path.stroke()
    }
}
