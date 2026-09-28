import AppKit

/// A borderless, transparent window that floats above other apps and holds the pet.
final class PetPanel: NSPanel {
    /// Builds the right-click menu fresh each time, so it reflects the current timer state.
    var menuProvider: (() -> NSMenu)? {
        get { petView.menuProvider }
        set { petView.menuProvider = newValue }
    }

    /// Called on a plain click (press and release without dragging).
    var onClick: (() -> Void)? {
        get { petView.onClick }
        set { petView.onClick = newValue }
    }

    private let petView: PetView
    private(set) var scale: CGFloat

    /// `scale` is how many points each image pixel is drawn as.
    init(image: NSImage, scale: CGFloat) {
        let size = Self.size(forScale: scale)
        petView = PetView(frame: NSRect(origin: .zero, size: size))
        petView.image = image
        self.scale = scale

        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        contentView = petView

        if setFrameUsingName("PetWindow") {
            // The saved frame may be from a different size; keep its position, apply the current size.
            setScale(scale)
        } else {
            placeInDefaultPosition()
        }
        setFrameAutosaveName("PetWindow")
        keepOnScreen()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func setImage(_ image: NSImage) {
        petView.image = image
    }

    /// Resizes the pet, keeping its feet (bottom center) in the same spot.
    func setScale(_ scale: CGFloat) {
        self.scale = scale
        let newSize = Self.size(forScale: scale)
        let anchor = NSPoint(x: frame.midX, y: frame.minY)
        let newFrame = NSRect(
            x: (anchor.x - newSize.width / 2).rounded(),
            y: anchor.y,
            width: newSize.width,
            height: newSize.height
        )
        setFrame(newFrame, display: true)
    }

    /// The top of the pet's head, in screen coordinates (where the speech bubble points).
    /// Tied to pet.png: the head spans image columns 1–12 and its ear tips sit on row 1.
    var headTop: NSPoint {
        NSPoint(x: frame.minX + 6.5 * scale, y: frame.maxY - 1 * scale)
    }

    private static func size(forScale scale: CGFloat) -> NSSize {
        NSSize(
            width: PetRenderer.pixelSize.width * scale,
            height: PetRenderer.pixelSize.height * scale
        )
    }

    private func placeInDefaultPosition() {
        guard let visible = NSScreen.main?.visibleFrame else { return }
        setFrameOrigin(NSPoint(x: visible.maxX - frame.width - 40, y: visible.minY + 40))
    }

    /// If the saved position is on a screen that's no longer connected, bring the pet back.
    private func keepOnScreen() {
        let onSomeScreen = NSScreen.screens.contains { $0.visibleFrame.intersects(frame) }
        if !onSomeScreen { placeInDefaultPosition() }
    }
}

/// Draws the pet with crisp, unsmoothed pixels. Drag to move it; click to open its menu.
final class PetView: NSView {
    var menuProvider: (() -> NSMenu)?
    var onClick: (() -> Void)?

    /// How far the mouse must move before a press counts as a drag instead of a click.
    private static let dragThreshold: CGFloat = 3

    private var mouseDownLocation: NSPoint?
    private var windowOriginAtMouseDown: NSPoint?
    private var isDragging = false

    var image: NSImage? {
        didSet { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let image else { return }
        NSGraphicsContext.current?.imageInterpolation = .none
        image.draw(in: bounds)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        mouseDownLocation = NSEvent.mouseLocation
        windowOriginAtMouseDown = window?.frame.origin
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownLocation, let origin = windowOriginAtMouseDown else { return }
        let now = NSEvent.mouseLocation
        let dx = now.x - start.x, dy = now.y - start.y
        if !isDragging && hypot(dx, dy) < Self.dragThreshold { return }
        isDragging = true
        window?.setFrameOrigin(NSPoint(x: origin.x + dx, y: origin.y + dy))
    }

    override func mouseUp(with event: NSEvent) {
        if !isDragging && mouseDownLocation != nil { onClick?() }
        mouseDownLocation = nil
        windowOriginAtMouseDown = nil
        isDragging = false
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        menuProvider?()
    }
}

/// A menu item that runs a closure, so AppKit menus can be built without selectors.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func run() { handler() }
}
