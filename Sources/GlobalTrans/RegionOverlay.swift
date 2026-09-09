import AppKit
import CoreGraphics

@MainActor
final class RegionOverlayController {
    private var windows: [NSWindow] = []
    private var continuation: CheckedContinuation<CGRect?, Never>?

    func selectRegion() async -> CGRect? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            present()
        }
    }

    private func present() {
        cancelWindows()
        for screen in NSScreen.screens {
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.setFrame(screen.frame, display: true)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.level = .screenSaver
            window.ignoresMouseEvents = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.contentView = SelectionView(frame: NSRect(origin: .zero, size: screen.frame.size)) { [weak self] rect in
                self?.finish(rect)
            } onCancel: { [weak self] in
                self?.finish(nil)
            }
            window.makeKeyAndOrderFront(nil)
            windows.append(window)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func finish(_ rect: CGRect?) {
        cancelWindows()
        continuation?.resume(returning: rect)
        continuation = nil
    }

    private func cancelWindows() {
        for window in windows {
            window.orderOut(nil)
        }
        windows.removeAll()
    }
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
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.18).cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

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
        super.draw(dirtyRect)
        NSColor.black.withAlphaComponent(0.18).setFill()
        dirtyRect.fill()
        guard let start, let current else { return }
        let rect = NSRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
        NSColor.white.withAlphaComponent(0.12).setFill()
        rect.fill()
        NSColor.systemTeal.setStroke()
        let path = NSBezierPath(rect: rect)
        path.lineWidth = 2
        path.stroke()
    }
}
