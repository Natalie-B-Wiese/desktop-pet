import AppKit
import Observation
import SwiftUI

/// Where the bubble's tail points, in the bubble window's own coordinates.
@Observable
final class BubbleLayout {
    var tailX: CGFloat = 0
    var tailPointsUp = false
}

/// The "What would you like to do?" menu shown in the bubble when you click the cat.
@Observable
final class BubbleMenu {
    enum Page { case main, startTimer, timerControls }

    /// `nil` when the menu is closed.
    var page: Page? {
        didSet { if page != oldValue { onChange?() } }
    }

    @ObservationIgnored var onChange: (() -> Void)?

    var isOpen: Bool { page != nil }
}

/// What the menu buttons do. The menu closes itself before running these, except pause/resume.
struct BubbleActions {
    var startTimer: (_ duration: TimeInterval, _ label: String?) -> Void
    var stopTimer: () -> Void
    var togglePause: () -> Void
    var customize: () -> Void
    var hide: () -> Void
}

/// A small floating window above the pet's head that shows the timer or the click menu.
final class SpeechBubbleController {
    let menu = BubbleMenu()

    private let timer: PetTimer
    private let layout = BubbleLayout()
    private let panel: BubblePanel
    private let container: BubbleContainer
    private let hostingView: FirstClickHostingView<BubbleView>
    private weak var pet: PetPanel?
    private var observers: [NSObjectProtocol] = []
    private var outsideClickMonitor: Any?

    /// Space between the pet's head and the tip of the bubble's tail.
    private static let gap: CGFloat = 2

    init(timer: PetTimer, settings: PetSettings, pet: PetPanel, actions: BubbleActions) {
        self.timer = timer
        self.pet = pet

        let menu = self.menu
        let closingActions = BubbleActions(
            startTimer: { duration, label in menu.page = nil; actions.startTimer(duration, label) },
            stopTimer: { menu.page = nil; actions.stopTimer() },
            togglePause: actions.togglePause, // stays on the Timer page so you can see it change
            customize: { menu.page = nil; actions.customize() },
            hide: { menu.page = nil; actions.hide() }
        )

        hostingView = FirstClickHostingView(rootView: BubbleView(
            timer: timer, settings: settings, layout: layout, menu: menu, actions: closingActions
        ))
        container = BubbleContainer()
        container.addSubview(hostingView)

        panel = BubblePanel(
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

        // Clicking the bubble pauses/resumes a countdown, or closes "Time's up!".
        container.onClick = { [weak timer] in
            guard let timer else { return }
            if timer.state == .finished {
                timer.stop()
            } else if timer.hasCountdown {
                timer.togglePause()
            }
        }
        menu.onChange = { [weak self] in self?.menuChanged() }

        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            observers.append(NotificationCenter.default.addObserver(
                forName: name, object: pet, queue: .main
            ) { [weak self] _ in self?.update() })
        }
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
    }

    func toggleMenu() {
        menu.page = menu.isOpen ? nil : .main
    }

    /// Shows, hides or repositions the bubble to match the timer, the menu and the pet.
    func update() {
        guard let pet, pet.isVisible, timer.isActive || menu.isOpen else {
            if let parent = panel.parent { parent.removeChildWindow(panel) }
            panel.orderOut(nil)
            return
        }

        // Menu buttons need real clicks; otherwise the whole bubble is one click target.
        container.passesClicksToContent = menu.isOpen

        // Only pages with text fields may take the keyboard. The Start page grabs it right away
        // (you're about to type minutes); the Timer page only when you click its label box.
        let allowsKeyboard = menu.page == .startTimer || menu.page == .timerControls
        let grabsKeyboard = menu.page == .startTimer
        if panel.isKeyWindow && !allowsKeyboard {
            // Ordering out hands the keyboard back to the app you were using; it's re-shown below.
            panel.orderOut(nil)
        }
        panel.acceptsKeyboard = allowsKeyboard

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
        if grabsKeyboard {
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFront(nil)
        }
    }

    private func menuChanged() {
        if menu.isOpen, outsideClickMonitor == nil {
            // Clicking anywhere in another app closes the menu.
            outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown]
            ) { [weak self] _ in self?.menu.page = nil }
        } else if !menu.isOpen, let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
        update()
    }
}

/// Can take keyboard focus (for the timer page's text fields) without activating the app,
/// so the app you were using stays in front.
private final class BubblePanel: NSPanel {
    var acceptsKeyboard = false
    override var canBecomeKey: Bool { acceptsKeyboard }
    override var canBecomeMain: Bool { false }
}

/// Either hands clicks to the SwiftUI buttons inside, or catches them all as one "click the bubble".
private final class BubbleContainer: NSView {
    var onClick: (() -> Void)?
    var passesClicksToContent = false

    override func hitTest(_ point: NSPoint) -> NSView? {
        if passesClicksToContent { return super.hitTest(point) }
        return frame.contains(point) ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        // While the menu is open, clicks the buttons don't take (e.g. on a disabled button)
        // bubble up to here; ignore them rather than treating them as "click the bubble".
        guard !passesClicksToContent else { return }
        onClick?()
    }
}

/// The bubble never becomes the active window, so its buttons must respond to the very first click.
private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct BubbleView: View {
    let timer: PetTimer
    let settings: PetSettings
    let layout: BubbleLayout
    let menu: BubbleMenu
    let actions: BubbleActions

    private static let tailHeight: CGFloat = 8

    var body: some View {
        content
            .foregroundStyle(.black)
            .padding(.horizontal, 12)
            .padding(.vertical, menu.isOpen ? 10 : 7)
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
            .environment(\.colorScheme, .light) // the bubble is always white, even in Dark Mode
    }

    @ViewBuilder
    private var content: some View {
        switch menu.page {
        case .main: mainMenu
        case .startTimer: timerMenu
        // If the countdown ends while this page is open, fall back to the main menu.
        case .timerControls: if timer.hasCountdown { timerControlsMenu } else { mainMenu }
        case nil: timerContent
        }
    }

    @ViewBuilder
    private var timerContent: some View {
        switch timer.state {
        case .running(let end):
            VStack(spacing: 0) {
                labelLine
                TimelineView(.periodic(from: .now, by: 0.25)) { context in
                    Text(PetTimer.format(end.timeIntervalSince(context.date)))
                        .font(.system(size: 16, weight: .bold, design: .rounded).monospacedDigit())
                }
            }
        case .paused(let remaining):
            VStack(spacing: 0) {
                labelLine
                HStack(spacing: 4) {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text(PetTimer.format(remaining))
                        .font(.system(size: 16, weight: .bold, design: .rounded).monospacedDigit())
                }
            }
            .opacity(0.5)
        case .finished:
            VStack(spacing: 1) {
                labelLine
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

    /// The timer's label in small type, if it has one.
    @ViewBuilder
    private var labelLine: some View {
        if let label = timer.displayLabel {
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 160)
        }
    }

    private var mainMenu: some View {
        VStack(spacing: 6) {
            Text(settings.displayName.map { "What should \($0) do?" } ?? "What would you like to do?")
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true) // long names wrap to a second line
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .padding(.bottom, 2)

            switch timer.state {
            case .idle:
                BubbleButton("Start a timer", systemImage: "timer") { menu.page = .startTimer }
            case .running, .paused:
                // All the countdown's options live one page down, keeping this menu short.
                // "Start a timer" is hidden meanwhile, so the countdown can't be overwritten by accident.
                TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                    BubbleButton(
                        "Timer (\(PetTimer.format(timer.remaining ?? 0)))",
                        systemImage: timer.state.isPaused ? "pause.circle" : "timer"
                    ) { menu.page = .timerControls }
                }
            case .finished:
                BubbleButton("Clear time's up", systemImage: "checkmark.circle", action: actions.stopTimer)
                BubbleButton("Start a timer", systemImage: "timer") { menu.page = .startTimer }
            }

            BubbleButton("Customize", systemImage: "paintpalette", action: actions.customize)
            BubbleButton("Hide", systemImage: "eye.slash", action: actions.hide)
            BubbleButton("Never mind", systemImage: "xmark", style: .quiet) { menu.page = nil }
        }
        .frame(width: 190)
    }

    /// The remaining time in large type, with a pause symbol when paused. Redraws itself.
    private var bigReadout: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            HStack(spacing: 5) {
                if timer.state.isPaused {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 14, weight: .bold))
                }
                Text(PetTimer.format(timer.remaining ?? 0))
                    .font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit())
            }
        }
    }

    private var timerControlsMenu: some View {
        VStack(spacing: 6) {
            Text("Timer")
                .font(.system(size: 13, weight: .bold, design: .rounded))
            bigReadout

            // Redraws every quarter second so the greyed-out buttons stay current.
            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                HStack(spacing: 4) {
                    ForEach(PetTimer.editSteps, id: \.self) { step in
                        let allowed = timer.canAdjust(bySeconds: step)
                        BubbleButton(PetTimer.shortEditTitle(step), centered: true) {
                            timer.adjust(bySeconds: step)
                        }
                        .disabled(!allowed)
                        .opacity(allowed ? 1 : 0.35)
                    }
                }
            }

            // Edits the running timer's label live; Return or Esc closes the menu.
            TextField("Label (optional)", text: TimerDraft.limited(Binding(
                get: { timer.label ?? "" },
                set: { timer.label = $0 }
            )))
            .bubbleFieldStyle()
            .onSubmit { menu.page = nil }
            .onExitCommand { menu.page = nil }
            .padding(.bottom, 2)

            if timer.state.isPaused {
                BubbleButton("Resume", systemImage: "play.circle", action: actions.togglePause)
            } else {
                BubbleButton("Pause", systemImage: "pause.circle", action: actions.togglePause)
            }
            BubbleButton("Stop timer", systemImage: "stop.circle", action: actions.stopTimer)
            BubbleButton("Back", systemImage: "chevron.left", style: .quiet) { menu.page = .main }
        }
        .frame(width: 190)
    }

    private var timerMenu: some View {
        BubbleTimerPage(
            onStart: actions.startTimer,
            onBack: { menu.page = .main },
            onClose: { menu.page = nil }
        )
        .frame(width: 190)
    }
}

/// "How long?": type the minutes or nudge them, then Start.
private struct BubbleTimerPage: View {
    var onStart: (_ duration: TimeInterval, _ label: String?) -> Void
    var onBack: () -> Void
    var onClose: () -> Void

    @AppStorage(TimerDraft.minutesKey) private var minutes = TimerDraft.defaultMinutes
    @State private var label = ""
    @FocusState private var minutesFocused: Bool

    private var duration: TimeInterval { TimeInterval(minutes * 60) }

    var body: some View {
        VStack(spacing: 8) {
            Text("How long?")
                .font(.system(size: 13, weight: .bold, design: .rounded))

            field("minutes", value: $minutes, range: TimerDraft.minuteRange)
                .focused($minutesFocused)

            HStack(spacing: 4) {
                ForEach(TimerDraft.steps, id: \.self) { step in
                    BubbleButton(TimerDraft.stepTitle(step), centered: true) {
                        TimerDraft.adjust(&minutes, by: step)
                    }
                }
            }

            TextField("Label (optional)", text: TimerDraft.limited($label))
                .bubbleFieldStyle()
                .onSubmit(start) // Return starts the timer

            BubbleButton("Start", systemImage: "play.fill", action: start)
                .disabled(duration <= 0)
                .opacity(duration <= 0 ? 0.4 : 1)
            BubbleButton("Back", systemImage: "chevron.left", style: .quiet, action: onBack)
        }
        .onAppear {
            // Wait a moment for the bubble to become the key window before focusing.
            DispatchQueue.main.async { minutesFocused = true }
        }
        .onExitCommand(perform: onClose) // Esc closes the menu
    }

    private func start() {
        guard duration > 0 else { return }
        onStart(duration, TimerDraft.cleanLabel(label))
    }

    private func field(_ unit: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        VStack(spacing: 1) {
            TextField(unit, text: TimerDraft.digits(value, in: range))
                .textFieldStyle(.plain)
                .font(.system(size: 22, weight: .bold, design: .rounded).monospacedDigit())
                .multilineTextAlignment(.center)
                .frame(width: 72)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 7).fill(.white))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(.black, lineWidth: 1.5))
                .onSubmit(start) // Return starts the timer
                // Beside the box without shifting it off-center.
                .overlay(alignment: .trailing) {
                    CaretStepper(
                        canIncrement: value.wrappedValue < range.upperBound,
                        canDecrement: value.wrappedValue > range.lowerBound,
                        increment: { value.wrappedValue += 1 },
                        decrement: { value.wrappedValue -= 1 }
                    )
                    .offset(x: 26)
                }
            Text(unit)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .opacity(0.55)
        }
    }
}

extension View {
    /// A white, black-outlined text box that matches the bubble.
    func bubbleFieldStyle() -> some View {
        textFieldStyle(.plain)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 7).fill(.white))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(.black, lineWidth: 1.5))
    }
}

/// A white, black-outlined button that matches the bubble.
struct BubbleButton: View {
    enum Style { case normal, quiet }

    let title: String
    let systemImage: String?
    let style: Style
    let centered: Bool
    let action: () -> Void

    init(
        _ title: String,
        systemImage: String? = nil,
        style: Style = .normal,
        centered: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.style = style
        self.centered = centered
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .frame(width: 16)
                }
                Text(title)
                    .monospacedDigit()
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .padding(.horizontal, centered ? 4 : 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(BubbleButtonStyle(style: style))
    }
}

private struct BubbleButtonStyle: ButtonStyle {
    let style: BubbleButton.Style

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 7)
        configuration.label
            .foregroundStyle(style == .quiet ? Color.black.opacity(0.6) : .black)
            .background(shape.fill(configuration.isPressed ? Color.black.opacity(0.12) : .white))
            .overlay(shape.stroke(Color.black.opacity(style == .quiet ? 0.25 : 1), lineWidth: 1.5))
    }
}

/// Up/down carets like a number input's.
private struct CaretStepper: View {
    var canIncrement: Bool
    var canDecrement: Bool
    var increment: () -> Void
    var decrement: () -> Void

    var body: some View {
        VStack(spacing: 2) {
            caret("chevron.up", enabled: canIncrement, action: increment)
            caret("chevron.down", enabled: canDecrement, action: decrement)
        }
        .buttonRepeatBehavior(.enabled) // hold to keep counting
    }

    private func caret(_ systemImage: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 8, weight: .heavy))
                .frame(width: 20, height: 13)
                .contentShape(Rectangle())
        }
        .buttonStyle(CaretButtonStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
    }
}

private struct CaretButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 4)
        configuration.label
            .foregroundStyle(.black)
            .background(shape.fill(configuration.isPressed ? Color.black.opacity(0.12) : .white))
            .overlay(shape.stroke(.black, lineWidth: 1.5))
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
