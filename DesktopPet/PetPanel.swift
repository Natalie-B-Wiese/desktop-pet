import AppKit

/// A borderless, transparent window that floats above other apps and holds the pet.
final class PetPanel: NSPanel {
    var onHide: (() -> Void)?
    var onCustomize: (() -> Void)?

    private let petView: PetView

    /// `scale` is how many points each image pixel is drawn as.
    init(image: NSImage, scale: CGFloat) {
        let size = Self.size(forScale: scale)
        petView = PetView(frame: NSRect(origin: .zero, size: size))
        petView.image = image

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

        petView.menu = makeContextMenu()

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

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "Customize…", action: #selector(customizeClicked), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Hide Pet", action: #selector(hideClicked), keyEquivalent: "").target = self
        return menu
    }

    @objc private func customizeClicked() { onCustomize?() }
    @objc private func hideClicked() { onHide?() }
}

/// Draws the pet with crisp, unsmoothed pixels and lets you drag it around.
final class PetView: NSView {
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
        window?.performDrag(with: event)
    }
}
