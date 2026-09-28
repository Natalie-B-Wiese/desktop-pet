import AppKit

/// A borderless, transparent window that floats above other apps and holds the pet.
final class PetPanel: NSPanel {
    /// Each image pixel is drawn as a 6×6 point block.
    static let scale: CGFloat = 6

    var onHide: (() -> Void)?
    var onCustomize: (() -> Void)?

    private let petView: PetView

    init(image: NSImage) {
        let size = NSSize(
            width: PetRenderer.pixelSize.width * Self.scale,
            height: PetRenderer.pixelSize.height * Self.scale
        )
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

        if !setFrameUsingName("PetWindow") {
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
