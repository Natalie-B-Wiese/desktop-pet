import AppKit
import Observation
import SwiftUI

/// Where the bubble's tail points, in the bubble window's own coordinates.
@Observable
final class BubbleLayout {
    var tailX: CGFloat = 0
    var tailPointsUp = false

    /// Called when the bubble's contents change size (e.g. switching Timer/Pomodoro tabs),
    /// so its window can be resized to fit.
    @ObservationIgnored var onContentSizeChange: (() -> Void)?
}

/// The "What would you like to do?" menu shown in the bubble when you click the cat.
@Observable
final class BubbleMenu {
    enum Page { case main, startTimer, timerControls, reminders, addReminder }

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
    var startPomodoro: (_ work: TimeInterval, _ rest: TimeInterval) -> Void
    var startStopwatch: (_ label: String?) -> Void
    var stopTimer: () -> Void
    var togglePause: () -> Void
    var startNextPomodoroPeriod: () -> Void
    var customize: () -> Void
    var hide: () -> Void
    var openRemindersWindow: () -> Void
}

/// A small floating window above the pet's head that shows the timer or the click menu.
final class SpeechBubbleController {
    let menu = BubbleMenu()

    private let timer: PetTimer
    private let reminders: ReminderStore
    private let layout = BubbleLayout()
    private let panel: BubblePanel
    private let container: BubbleContainer
    private let hostingView: FirstClickHostingView<BubbleView>
    private weak var pet: PetPanel?
    private var observers: [NSObjectProtocol] = []
    private var outsideClickMonitor: Any?

    /// Space between the pet's head and the tip of the bubble's tail.
    private static let gap: CGFloat = 2

    init(timer: PetTimer, reminders: ReminderStore, settings: PetSettings, pet: PetPanel, actions: BubbleActions) {
        self.timer = timer
        self.reminders = reminders
        self.pet = pet

        let menu = self.menu
        let closingActions = BubbleActions(
            startTimer: { duration, label in menu.page = nil; actions.startTimer(duration, label) },
            startPomodoro: { work, rest in menu.page = nil; actions.startPomodoro(work, rest) },
            startStopwatch: { label in menu.page = nil; actions.startStopwatch(label) },
            stopTimer: { menu.page = nil; actions.stopTimer() },
            togglePause: actions.togglePause, // stays on the Timer page so you can see it change
            startNextPomodoroPeriod: { menu.page = nil; actions.startNextPomodoroPeriod() },
            customize: { menu.page = nil; actions.customize() },
            hide: { menu.page = nil; actions.hide() },
            openRemindersWindow: { menu.page = nil; actions.openRemindersWindow() }
        )

        hostingView = FirstClickHostingView(rootView: BubbleView(
            timer: timer, reminders: reminders, settings: settings,
            layout: layout, menu: menu, actions: closingActions
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

        // Clicking the bubble closes a due reminder or "Time's up!", or pauses/resumes a countdown.
        container.onClick = { [weak timer, weak reminders] in
            guard let timer, let reminders else { return }
            if !reminders.due.isEmpty {
                reminders.dismissFirstDue()
            } else if timer.state == .finished {
                if timer.pomodoro != nil { timer.startNextPomodoroPeriod() } else { timer.stop() }
            } else if timer.hasCountdown {
                timer.togglePause()
            }
        }
        menu.onChange = { [weak self] in self?.menuChanged() }
        layout.onContentSizeChange = { [weak self] in
            // Resize on the next pass, not in the middle of SwiftUI's layout.
            DispatchQueue.main.async { self?.update() }
        }

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
        guard let pet, pet.isVisible, timer.isActive || menu.isOpen || !reminders.due.isEmpty else {
            if let parent = panel.parent { parent.removeChildWindow(panel) }
            panel.orderOut(nil)
            return
        }

        // Menu buttons need real clicks; otherwise the whole bubble is one click target.
        container.passesClicksToContent = menu.isOpen

        // Only pages with text fields may take the keyboard. The Start page grabs it right away
        // (you're about to type minutes); the Timer page only when you click its label box.
        let grabsKeyboard = menu.page == .startTimer || menu.page == .addReminder
        let allowsKeyboard = grabsKeyboard || menu.page == .timerControls
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
    let reminders: ReminderStore
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
            .onGeometryChange(for: CGSize.self, of: \.size) { _ in
                layout.onContentSizeChange?()
            }
    }

    @ViewBuilder
    private var content: some View {
        switch menu.page {
        case .main: mainMenu
        case .startTimer: timerMenu
        // If the countdown ends while this page is open, fall back to the main menu.
        case .timerControls: if timer.hasCountdown { timerControlsMenu } else { mainMenu }
        case .reminders:
            BubbleRemindersPage(
                store: reminders,
                onAdd: { menu.page = .addReminder },
                onOpenWindow: actions.openRemindersWindow,
                onBack: { menu.page = .main }
            )
            .frame(width: 190)
        case .addReminder:
            BubbleAddReminderPage(
                store: reminders,
                onAdded: { menu.page = .reminders },
                onBack: { menu.page = .reminders },
                onClose: { menu.page = nil }
            )
            .frame(width: 190)
        case nil:
            // A due reminder takes priority; the timer shows again once it's closed.
            if let reminder = reminders.due.first {
                BubbleReminderAlert(reminder: reminder, moreCount: reminders.due.count - 1)
            } else {
                timerContent
            }
        }
    }

    @ViewBuilder
    private var timerContent: some View {
        switch timer.state {
        case .running:
            VStack(spacing: 0) {
                labelLine
                TimelineView(.periodic(from: .now, by: 0.25)) { context in
                    HStack(spacing: 4) {
                        stopwatchIcon
                        Text(timer.formattedTime(at: context.date))
                            .font(.system(size: 16, weight: .bold, design: .rounded).monospacedDigit())
                    }
                }
            }
        case .paused:
            VStack(spacing: 0) {
                labelLine
                HStack(spacing: 4) {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text(timer.formattedTime())
                        .font(.system(size: 16, weight: .bold, design: .rounded).monospacedDigit())
                }
            }
            .opacity(0.5)
        case .finished:
            if let pomodoro = timer.pomodoro {
                // A Pomodoro period ended; clicking starts the next one.
                VStack(spacing: 1) {
                    Text(pomodoro.phase == .work ? "Break time!" : "Back to work!")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text(pomodoro.phase == .work
                         ? "Click to start \(pomodoro.breakMinutes)-min break"
                         : "Click to start work session")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .opacity(0.55)
                }
            } else {
                VStack(spacing: 1) {
                    labelLine
                    Text("Time's up!")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text("Click to close")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .opacity(0.55)
                }
            }
        case .idle:
            EmptyView()
        }
    }

    /// A small ⏱ so a stopwatch (counting up) doesn't look like a countdown.
    @ViewBuilder
    private var stopwatchIcon: some View {
        if timer.isStopwatch {
            Image(systemName: "stopwatch")
                .font(.system(size: 11, weight: .bold))
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
                        "\(timer.isStopwatch ? "Stopwatch" : "Timer") (\(timer.formattedTime()))",
                        systemImage: timer.state.isPaused ? "pause.circle" : timer.isStopwatch ? "stopwatch" : "timer"
                    ) { menu.page = .timerControls }
                }
            case .finished:
                if let pomodoro = timer.pomodoro {
                    BubbleButton(
                        pomodoro.phase == .work ? "Start break" : "Start work session",
                        systemImage: "play.circle",
                        action: actions.startNextPomodoroPeriod
                    )
                    BubbleButton("Stop Pomodoro", systemImage: "stop.circle", action: actions.stopTimer)
                } else {
                    BubbleButton("Clear time's up", systemImage: "checkmark.circle", action: actions.stopTimer)
                    BubbleButton("Start a timer", systemImage: "timer") { menu.page = .startTimer }
                }
            }

            let upcomingCount = reminders.upcoming.count
            BubbleButton(
                upcomingCount > 0 ? "Reminders (\(upcomingCount))" : "Reminders",
                systemImage: "bell"
            ) { menu.page = .reminders }

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
                Text(timer.formattedTime())
                    .font(.system(size: 26, weight: .bold, design: .rounded).monospacedDigit())
            }
        }
    }

    private var timerControlsMenu: some View {
        VStack(spacing: 6) {
            if let label = timer.displayLabel, timer.pomodoro != nil {
                // Pomodoro: the period ("Work" or "Break") is the title; there's no label to edit.
                Text(label)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
            } else {
                Text(timer.kindTitle)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
            }
            bigReadout

            if !timer.isStopwatch { // a stopwatch just counts; there's nothing to add or subtract
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
            }

            if timer.pomodoro == nil {
                // Edits the running timer's label live; Return or Esc closes the menu.
                TextField("Label (optional)", text: TimerDraft.limited(Binding(
                    get: { timer.label ?? "" },
                    set: { timer.label = $0 }
                )))
                .bubbleFieldStyle()
                .onSubmit { menu.page = nil }
                .onExitCommand { menu.page = nil }
                .padding(.bottom, 2)
            }

            if timer.state.isPaused {
                BubbleButton("Resume", systemImage: "play.circle", action: actions.togglePause)
            } else {
                BubbleButton("Pause", systemImage: "pause.circle", action: actions.togglePause)
            }
            BubbleButton(
                timer.pomodoro != nil ? "Stop Pomodoro" : "Stop \(timer.kindTitle.lowercased())",
                systemImage: "stop.circle",
                action: actions.stopTimer
            )
            BubbleButton("Back", systemImage: "chevron.left", style: .quiet) { menu.page = .main }
        }
        .frame(width: 190)
    }

    private var timerMenu: some View {
        BubbleTimerPage(
            onStart: actions.startTimer,
            onStartPomodoro: actions.startPomodoro,
            onStartStopwatch: actions.startStopwatch,
            onBack: { menu.page = .main },
            onClose: { menu.page = nil }
        )
        .frame(width: 228) // a little wider than other pages, to fit three tabs
    }
}

/// The Start page: a plain timer (minutes and label) or Pomodoro (work and break lengths).
private struct BubbleTimerPage: View {
    enum Mode: String { case timer, pomodoro, stopwatch }

    var onStart: (_ duration: TimeInterval, _ label: String?) -> Void
    var onStartPomodoro: (_ work: TimeInterval, _ rest: TimeInterval) -> Void
    var onStartStopwatch: (_ label: String?) -> Void
    var onBack: () -> Void
    var onClose: () -> Void

    @AppStorage("startPage.mode") private var mode = Mode.timer
    @AppStorage(TimerDraft.minutesKey) private var minutes = TimerDraft.defaultMinutes
    @AppStorage(TimerDraft.pomodoroWorkKey) private var workMinutes = TimerDraft.defaultWorkMinutes
    @AppStorage(TimerDraft.pomodoroBreakKey) private var breakMinutes = TimerDraft.defaultBreakMinutes
    @State private var label = ""
    @FocusState private var firstFieldFocused: Bool

    private var duration: TimeInterval { TimeInterval(minutes * 60) }
    private var canStart: Bool {
        switch mode {
        case .timer: minutes > 0
        case .pomodoro: workMinutes > 0 && breakMinutes > 0
        case .stopwatch: true
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            BubbleTabs(selection: $mode, options: [(.timer, "Timer"), (.stopwatch, "Stopwatch"), (.pomodoro, "Pomodoro")])

            switch mode {
            case .timer: timerForm
            case .stopwatch: stopwatchForm
            case .pomodoro: pomodoroForm
            }

            BubbleButton("Start", systemImage: "play.fill", action: start)
                .disabled(!canStart)
                .opacity(canStart ? 1 : 0.4)
            BubbleButton("Back", systemImage: "chevron.left", style: .quiet, action: onBack)
        }
        .onAppear {
            // Wait a moment for the bubble to become the key window before focusing.
            DispatchQueue.main.async { firstFieldFocused = true }
        }
        .onChange(of: mode) { firstFieldFocused = true }
        .onExitCommand(perform: onClose) // Esc closes the menu
    }

    @ViewBuilder
    private var timerForm: some View {
        VStack(spacing: 1) {
            numberBox($minutes, range: TimerDraft.minuteRange, width: 72, fontSize: 22)
                .focused($firstFieldFocused)
                // Beside the box without shifting it off-center.
                .overlay(alignment: .trailing) {
                    stepper($minutes, range: TimerDraft.minuteRange).offset(x: 26)
                }
            Text("minutes")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .opacity(0.55)
        }

        TextField("Label (optional)", text: TimerDraft.limited($label))
            .bubbleFieldStyle()
            .onSubmit(start) // Return starts the timer
    }

    @ViewBuilder
    private var pomodoroForm: some View {
        VStack(spacing: 6) {
            pomodoroRow("Work", $workMinutes)
                .focused($firstFieldFocused)
            pomodoroRow("Break", $breakMinutes)
        }
        .padding(.vertical, 2)
    }

    private var stopwatchForm: some View {
        TextField("Label (optional)", text: TimerDraft.limited($label))
            .bubbleFieldStyle()
            .focused($firstFieldFocused)
            .onSubmit(start) // Return starts the stopwatch
    }

    private func pomodoroRow(_ title: String, _ value: Binding<Int>) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .frame(width: 42, alignment: .leading)
            numberBox(value, range: TimerDraft.pomodoroRange, width: 52, fontSize: 18)
            stepper(value, range: TimerDraft.pomodoroRange)
            Text("min")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .opacity(0.55)
        }
    }

    private func numberBox(_ value: Binding<Int>, range: ClosedRange<Int>, width: CGFloat, fontSize: CGFloat) -> some View {
        TextField("", text: TimerDraft.digits(value, in: range))
            .textFieldStyle(.plain)
            .font(.system(size: fontSize, weight: .bold, design: .rounded).monospacedDigit())
            .multilineTextAlignment(.center)
            .frame(width: width)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 7).fill(.white))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(.black, lineWidth: 1.5))
            .onSubmit(start) // Return starts
    }

    private func stepper(_ value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        CaretStepper(
            canIncrement: value.wrappedValue < range.upperBound,
            canDecrement: value.wrappedValue > range.lowerBound,
            increment: { value.wrappedValue += 1 },
            decrement: { value.wrappedValue -= 1 }
        )
    }

    private func start() {
        guard canStart else { return }
        switch mode {
        case .timer:
            onStart(duration, TimerDraft.cleanLabel(label))
        case .pomodoro:
            onStartPomodoro(TimeInterval(workMinutes * 60), TimeInterval(breakMinutes * 60))
        case .stopwatch:
            onStartStopwatch(TimerDraft.cleanLabel(label))
        }
    }
}

/// Two or more tabs styled like the bubble: the selected one is filled black.
private struct BubbleTabs<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(Value, String)]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.0) { value, title in
                let selected = value == selection
                Button {
                    selection = value
                } label: {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8) // three tabs share a narrow bubble
                        .foregroundStyle(selected ? Color.white : .black)
                        .padding(.horizontal, 4)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(selected ? Color.black : .white)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(.black, lineWidth: 1.5))
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
