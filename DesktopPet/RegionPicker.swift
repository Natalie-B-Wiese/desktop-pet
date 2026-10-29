import AppKit

/// Dims every screen and lets you drag out the part to record, like the screenshot crosshair.
/// Clicking without dragging picks the whole screen under the mouse; Esc cancels.
final class RegionPicker {
    /// The region (nil for the whole screen) and its screen, or nil if cancelled.
    typealias Completion = ((region: NSRect?, screen: NSScreen)?) -> Void

    private var windows: [NSWindow] = []
    private var completion: Completion?
    private var previousApp: NSRunningApplication?

    func pick(completion: @escaping Completion) {
        guard windows.isEmpty else { return }
        self.completion = completion
        // The overlay takes the keyboard for Esc, then hands it back to the app you were using.
        previousApp = NSWorkspace.shared.frontmostApplication
        for screen in NSScreen.screens {
            let window = PickerWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.isReleasedWhenClosed = false
            let view = RegionView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.onDone = { [weak self, weak window] rect in
                guard let self else { return }
                finish(rect.map { local in
                    let origin = window?.frame.origin ?? .zero
                    return (local.offsetBy(dx: origin.x, dy: origin.y), screen)
                })
            }
            view.onCancel = { [weak self] in self?.finish(nil) }
            window.contentView = view
            windows.append(window)
        }
        NSApp.activate()
        for window in windows { window.orderFrontRegardless() }
        // The window under the mouse takes the keyboard.
        let mouse = NSEvent.mouseLocation
        (windows.first { $0.frame.contains(mouse) } ?? windows.first)?.makeKey()
    }

    /// `picked.region` is in screen coordinates; a click (no drag) is the whole screen.
    private func finish(_ picked: (region: NSRect, screen: NSScreen)?) {
        windows.forEach { $0.orderOut(nil) }
        windows = []
        previousApp?.activate()
        previousApp = nil
        let completion = self.completion
        self.completion = nil
        guard let picked else { completion?(nil); return }
        let isClick = picked.region.width < 4 || picked.region.height < 4
        completion?((isClick ? nil : picked.region, picked.screen))
    }
}

private final class PickerWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

/// The dimmed screen with the dragged region cut out, outlined, and its size shown.
private final class RegionView: NSView {
    /// The region in this view's coordinates (zero-sized for a click).
    var onDone: ((NSRect?) -> Void)?
    var onCancel: (() -> Void)?

    private var start: NSPoint?
    private var current: NSPoint?

    private var selection: NSRect? {
        guard let start, let current else { return nil }
        return NSRect(x: min(start.x, current.x), y: min(start.y, current.y),
                      width: abs(current.x - start.x), height: abs(current.y - start.y)).integral
    }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func viewDidMoveToWindow() {
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?() } else { super.keyDown(with: event) } // Esc
    }

    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil)
        current = start
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        current = NSPoint(x: min(max(point.x, 0), bounds.maxX), y: min(max(point.y, 0), bounds.maxY))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let rect = selection
        start = nil
        current = nil
        onDone?(rect)
    }

    override func draw(_ dirtyRect: NSRect) {
        let dim = NSBezierPath(rect: bounds)
        if let selection, selection.width > 0, selection.height > 0 {
            dim.append(NSBezierPath(rect: selection))
            dim.windingRule = .evenOdd
        }
        NSColor.black.withAlphaComponent(0.3).setFill()
        dim.fill()

        guard let selection, selection.width >= 4, selection.height >= 4 else {
            drawHint()
            return
        }
        NSColor.white.setStroke()
        let outline = NSBezierPath(rect: selection.insetBy(dx: -1, dy: -1))
        outline.lineWidth = 2
        outline.stroke()

        // "640 × 480" just under the region, or inside it near the bottom of the screen.
        let label = "\(Int(selection.width)) × \(Int(selection.height))" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let size = label.size(withAttributes: attributes)
        var box = NSRect(x: selection.maxX - size.width - 12, y: selection.minY - size.height - 12,
                         width: size.width + 12, height: size.height + 6)
        if box.minY < bounds.minY { box.origin.y = selection.minY + 6 }
        box.origin.x = max(box.minX, bounds.minX + 4)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: box, xRadius: 5, yRadius: 5).fill()
        label.draw(at: NSPoint(x: box.minX + 6, y: box.minY + 3), withAttributes: attributes)
    }

    /// What to do, in the middle of the screen, until a drag starts.
    private func drawHint() {
        let hint = "Drag to record part of the screen, or click to record all of it. Esc cancels." as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let size = hint.size(withAttributes: attributes)
        let box = NSRect(x: bounds.midX - size.width / 2 - 14, y: bounds.midY - size.height / 2 - 8,
                         width: size.width + 28, height: size.height + 16)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: box, xRadius: 9, yRadius: 9).fill()
        hint.draw(at: NSPoint(x: box.minX + 14, y: box.minY + 8), withAttributes: attributes)
    }
}
