import AppKit
import Observation
import SwiftUI

/// Where the bubble's tail points, in the bubble window's own coordinates.
@Observable
final class BubbleLayout {
    var tailX: CGFloat = 0
    var tailPointsUp = false
}

/// A small floating window above the pet's head that shows the timer.
final class SpeechBubbleController {
    private let timer: PetTimer
    private let layout = BubbleLayout()
    private let panel: NSPanel
    private let container: ClickableContainer
    private let hostingView: NSHostingView<BubbleView>
    private weak var pet: PetPanel?
    private var observers: [NSObjectProtocol] = []

    /// Space between the pet's head and the tip of the bubble's tail.
    private static let gap: CGFloat = 2

    init(timer: PetTimer, pet: PetPanel) {
        self.timer = timer
        self.pet = pet

        hostingView = NSHostingView(rootView: BubbleView(timer: timer, layout: layout))
        container = ClickableContainer()
        container.addSubview(hostingView)

        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.contentView = container

        container.onClick = { [weak timer] in
            if timer?.state == .finished { timer?.stop() }
        }

        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            observers.append(NotificationCenter.default.addObserver(
                forName: name, object: pet, queue: .main
            ) { [weak self] _ in self?.update() })
        }
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    /// Shows, hides or repositions the bubble to match the timer and the pet.
    func update() {
        guard let pet, pet.isVisible, timer.isActive else {
            if let parent = panel.parent { parent.removeChildWindow(panel) }
            panel.orderOut(nil)
            return
        }

        hostingView.layoutSubtreeIfNeeded()
        let size = hostingView.fittingSize
        let anchor = pet.headTop
        let screen = (pet.screen ?? NSScreen.main)?.visibleFrame ?? .infinite

        let fitsAbove = anchor.y + Self.gap + size.height <= screen.maxY
        let x = min(max(anchor.x - size.width / 2, screen.minX + 4), screen.maxX - size.width - 4)
        let y = fitsAbove ? anchor.y + Self.gap : pet.frame.minY - Self.gap - size.height

        layout.tailX = anchor.x - x
        layout.tailPointsUp = !fitsAbove

        let frame = NSRect(x: x.rounded(), y: y.rounded(), width: size.width, height: size.height)
        panel.setFrame(frame, display: true)
        hostingView.frame = container.bounds
        if panel.parent == nil { pet.addChildWindow(panel, ordered: .above) }
        panel.orderFront(nil)
    }
}

/// Catches clicks anywhere on the bubble (SwiftUI content inside doesn't need its own gestures).
private final class ClickableContainer: NSView {
    var onClick: (() -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}

struct BubbleView: View {
    let timer: PetTimer
    let layout: BubbleLayout

    private static let tailHeight: CGFloat = 8

    var body: some View {
        content
            .foregroundStyle(.black)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(minWidth: 72)
            .padding(layout.tailPointsUp ? .top : .bottom, Self.tailHeight)
            .background {
                let shape = BubbleShape(
                    tailX: layout.tailX,
                    tailHeight: Self.tailHeight,
                    tailPointsUp: layout.tailPointsUp
                )
                shape.fill(.white)
                shape.stroke(.black, lineWidth: 2)
            }
            .padding(2) // room for the outline
            .fixedSize()
    }

    @ViewBuilder
    private var content: some View {
        switch timer.state {
        case .running(let end):
            TimelineView(.periodic(from: .now, by: 0.25)) { context in
                Text(PetTimer.format(end.timeIntervalSince(context.date)))
                    .font(.system(size: 16, weight: .bold, design: .rounded).monospacedDigit())
            }
        case .finished:
            VStack(spacing: 1) {
                Text("Time's up!")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                Text("Click to close")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .opacity(0.55)
            }
        case .idle:
            EmptyView()
        }
    }
}

/// A rounded rectangle with a little triangular tail pointing at the pet.
struct BubbleShape: Shape {
    var tailX: CGFloat
    var tailHeight: CGFloat
    var tailPointsUp: Bool

    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 10
        let tailHalfWidth: CGFloat = 7
        let body = tailPointsUp
            ? CGRect(x: rect.minX, y: rect.minY + tailHeight, width: rect.width, height: rect.height - tailHeight)
            : CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - tailHeight)

        // `tailX` is measured from the window's left edge; the shape sits 2pt in from it.
        let x = min(max(tailX - 2, body.minX + radius + tailHalfWidth), body.maxX - radius - tailHalfWidth)

        var path = Path(roundedRect: body, cornerRadius: radius)
        var tail = Path()
        if tailPointsUp {
            tail.move(to: CGPoint(x: x - tailHalfWidth, y: body.minY + 1))
            tail.addLine(to: CGPoint(x: x, y: rect.minY))
            tail.addLine(to: CGPoint(x: x + tailHalfWidth, y: body.minY + 1))
        } else {
            tail.move(to: CGPoint(x: x - tailHalfWidth, y: body.maxY - 1))
            tail.addLine(to: CGPoint(x: x, y: rect.maxY))
            tail.addLine(to: CGPoint(x: x + tailHalfWidth, y: body.maxY - 1))
        }
        tail.closeSubpath()
        path = path.union(tail)
        return path
    }
}
