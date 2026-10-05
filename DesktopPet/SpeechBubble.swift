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
    enum Page: Equatable {
        case main, startTimer, timerControls, reminders, addReminder, todos, notes, math, clipboard, customize, settings
        case editReminder(Reminder.ID)
    }

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
    var hide: () -> Void
    var takeScreenshot: () -> Void
    var pickColor: () -> Void
}

/// A small floating window above the pet's head that shows the timer or the click menu.
final class SpeechBubbleController {
    let menu = BubbleMenu()

    private let timer: PetTimer
    private let reminders: ReminderStore
    private let todos: TodoStore
    private let mathHistory = MathHistory()
    private let clipboard: ClipboardHistory
    private let notes: NoteStore
    private let layout = BubbleLayout()
    private let panel: BubblePanel
    private let container: BubbleContainer
    private let hostingView: FirstClickHostingView<BubbleView>
    private weak var pet: PetPanel?
    private var observers: [NSObjectProtocol] = []
    private var outsideClickMonitor: Any?

    /// Space between the pet's head and the tip of the bubble's tail.
    private static let gap: CGFloat = 2

    init(
        timer: PetTimer, reminders: ReminderStore, todos: TodoStore, notes: NoteStore,
        clipboard: ClipboardHistory, settings: PetSettings, pet: PetPanel, actions: BubbleActions
    ) {
        self.timer = timer
        self.notes = notes
        self.clipboard = clipboard
        self.reminders = reminders
        self.todos = todos
        self.pet = pet

        let menu = self.menu
        let closingActions = BubbleActions(
            startTimer: { duration, label in menu.page = nil; actions.startTimer(duration, label) },
            startPomodoro: { work, rest in menu.page = nil; actions.startPomodoro(work, rest) },
            startStopwatch: { label in menu.page = nil; actions.startStopwatch(label) },
            stopTimer: { menu.page = nil; actions.stopTimer() },
            togglePause: actions.togglePause, // stays on the Timer page so you can see it change
            startNextPomodoroPeriod: { menu.page = nil; actions.startNextPomodoroPeriod() },
            hide: { menu.page = nil; actions.hide() },
            takeScreenshot: { menu.page = nil; actions.takeScreenshot() },
            pickColor: { menu.page = nil; actions.pickColor() }
        )

        hostingView = FirstClickHostingView(rootView: BubbleView(
            timer: timer, reminders: reminders, todos: todos, mathHistory: mathHistory,
            notes: notes, clipboard: clipboard, settings: settings,
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

    /// Opens the menu straight to `page` (e.g. To-dos from the menu bar).
    func open(_ page: BubbleMenu.Page) {
        menu.page = page
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
        let grabsKeyboard = switch menu.page {
        case .startTimer, .addReminder, .editReminder, .math: true
        default: false
        }
        let allowsKeyboard = grabsKeyboard || [.timerControls, .todos, .notes, .customize].contains(menu.page)
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
            // Clicking anywhere in another app closes the main menu. Tool pages stay open, so you
            // don't lose what you typed and can look things up elsewhere; close them with ✕ or the pet.
            outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown]
            ) { [weak self] _ in
                if self?.menu.page == .main { self?.menu.page = nil }
            }
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
    let todos: TodoStore
    let mathHistory: MathHistory
    let notes: NoteStore
    let clipboard: ClipboardHistory
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
        if let page = menu.page.map(effectivePage) {
            VStack(spacing: 6) {
                header(for: page)
                pageBody(page)
            }
            .frame(width: Self.width(of: page))
        } else if let reminder = reminders.due.first {
            // A due reminder takes priority; the timer shows again once it's closed.
            BubbleReminderAlert(reminder: reminder, moreCount: reminders.due.count - 1)
        } else {
            timerContent
        }
    }

    /// The Timer page falls back to the main menu if there's no longer anything to show on it.
    private func effectivePage(_ page: BubbleMenu.Page) -> BubbleMenu.Page {
        if page == .timerControls, !timer.hasCountdown, !(timer.state == .finished && timer.pomodoro != nil) {
            return .main
        }
        return page
    }

    private static func width(of page: BubbleMenu.Page) -> CGFloat {
        switch page {
        case .main: 3 * MenuTile.width + 2 * tileSpacing
        case .startTimer: 228
        case .timerControls, .reminders, .addReminder, .editReminder, .settings: 190
        case .math, .todos: 210
        case .notes: 220
        case .clipboard: 250
        case .customize: 272
        }
    }

    private func title(for page: BubbleMenu.Page) -> String {
        switch page {
        case .main: settings.displayName.map { "What should \($0) do?" } ?? "What would you like to do?"
        case .startTimer: "New timer"
        case .timerControls:
            if timer.state == .finished, let pomodoro = timer.pomodoro {
                pomodoro.phase == .work ? "Break time!" : "Back to work!"
            } else if timer.pomodoro != nil {
                timer.displayLabel ?? "Pomodoro" // "Work" or "Break"
            } else {
                timer.kindTitle
            }
        case .reminders: "Reminders"
        case .addReminder: "Remind me at…"
        case .editReminder: "Edit reminder"
        case .todos: "To-dos"
        case .notes: "Notes"
        case .math: "Math"
        case .clipboard: "Clipboard"
        case .customize: "Customize"
        case .settings: "Settings"
        }
    }

    /// Where ‹ goes; nil on the main menu.
    private func backDestination(for page: BubbleMenu.Page) -> BubbleMenu.Page? {
        switch page {
        case .main: nil
        case .addReminder, .editReminder: .reminders
        default: .main
        }
    }

    /// ‹ on the left (except on the main menu), the title, and ✕ on the right.
    private func header(for page: BubbleMenu.Page) -> some View {
        ZStack(alignment: .top) {
            Text(title(for: page))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true) // long pet names wrap to a second line
                .padding(.horizontal, 24) // clear of the ‹ and ✕
                .padding(.top, 2)
            HStack {
                if let back = backDestination(for: page) {
                    HeaderIconButton(systemImage: "chevron.left", help: "Back") { menu.page = back }
                }
                Spacer(minLength: 0)
                HeaderIconButton(systemImage: "xmark", help: "Close") { menu.page = nil }
            }
        }
        .padding(.bottom, 2)
    }

    @ViewBuilder
    private func pageBody(_ page: BubbleMenu.Page) -> some View {
        switch page {
        case .main: mainMenu
        case .startTimer: timerMenu
        // If the countdown ends while this page is open, fall back to the main menu.
        case .timerControls:
            if timer.hasCountdown { timerControlsMenu } else { pomodoroBetweenPeriodsMenu }
        case .reminders:
            BubbleRemindersPage(
                store: reminders,
                onAdd: { menu.page = .addReminder },
                onEdit: { menu.page = .editReminder($0) }
            )
            .frame(width: 190)
        case .addReminder:
            BubbleAddReminderPage(
                store: reminders,
                onAdded: { menu.page = .reminders },
                onClose: { menu.page = nil }
            )
            .frame(width: 190)
        case .editReminder(let id):
            // If it came due or was deleted meanwhile, there's nothing left to edit.
            if let reminder = reminders.upcoming.first(where: { $0.id == id }) {
                BubbleAddReminderPage(
                    store: reminders,
                    editing: reminder,
                    onAdded: { menu.page = .reminders },
                    onClose: { menu.page = nil }
                )
                .id(id)
                .frame(width: 190)
            } else {
                Text("That reminder is gone")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .opacity(0.55)
                    .frame(width: 190)
                    .padding(.vertical, 4)
            }
        case .notes:
            BubbleNotesPage(store: notes, onClose: { menu.page = nil })
                .frame(width: 220)
        case .clipboard:
            BubbleClipboardPage(history: clipboard, onScreenshot: actions.takeScreenshot, onPickColor: actions.pickColor)
                .frame(width: 250) // room for the copy button and reorder arrows around the preview
        case .math:
            BubbleMathPage(history: mathHistory, onClose: { menu.page = nil })
                .frame(width: 210)
        case .customize:
            BubbleCustomizePage(settings: settings)
        case .settings:
            BubbleSettingsPage()
                .frame(width: 190)
        case .todos:
            BubbleTodoPage(store: todos, onClose: { menu.page = nil })
                .frame(width: 210)
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
            // Grouped rows: time things, tools, and the pet itself.
            HStack(spacing: Self.tileSpacing) {
                timerTile
                MenuTile("Reminders", systemImage: "bell", badge: reminders.upcoming.count) { menu.page = .reminders }
                MenuTile("To-dos", systemImage: "checklist", badge: todos.remainingCount) { menu.page = .todos }
            }
            HStack(spacing: Self.tileSpacing) {
                MenuTile("Notes", systemImage: "note.text", badge: notes.notes.count) { menu.page = .notes }
                MenuTile("Clipboard", systemImage: "doc.on.clipboard") { menu.page = .clipboard }
                MenuTile("Math", systemImage: "plus.forwardslash.minus") { menu.page = .math }
            }
            HStack(spacing: Self.tileSpacing) {
                MenuTile("Customize", systemImage: "paintpalette") { menu.page = .customize }
                MenuTile("Settings", systemImage: "gearshape") { menu.page = .settings }
                MenuTile("Hide", systemImage: "eye.slash", action: actions.hide)
            }

        }
        .frame(width: 3 * MenuTile.width + 2 * Self.tileSpacing)
    }

    private static let tileSpacing: CGFloat = 6

    /// The Timer tile follows the timer: "Timer" when idle, the live time while one runs,
    /// and "Time's up" (tap to clear) after a regular timer ends.
    @ViewBuilder
    private var timerTile: some View {
        switch timer.state {
        case .idle:
            MenuTile("Timer", systemImage: "timer") { menu.page = .startTimer }
        case .running, .paused:
            // "Start a timer" is out of reach meanwhile, so the countdown can't be overwritten by accident.
            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                MenuTile(
                    timer.formattedTime(),
                    systemImage: timer.state.isPaused ? "pause.circle" : timer.isStopwatch ? "stopwatch" : "timer",
                    monospacedLabel: true
                ) { menu.page = .timerControls }
            }
        case .finished:
            if let pomodoro = timer.pomodoro {
                // Between periods: the Timer page offers the next period or stopping.
                MenuTile(pomodoro.phase == .work ? "Break" : "Work", systemImage: "play.circle") {
                    menu.page = .timerControls
                }
            } else {
                // Clear the finished timer and go straight to setting up a new one.
                MenuTile("Time's up", systemImage: "checkmark.circle") {
                    timer.stop()
                    menu.page = .startTimer
                }
            }
        }
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

    /// The Timer page between Pomodoro periods: start the next one, or stop.
    private var pomodoroBetweenPeriodsMenu: some View {
        let onBreakNext = timer.pomodoro?.phase == .work
        return VStack(spacing: 6) {
            BubbleButton(
                onBreakNext ? "Start break" : "Start work session",
                systemImage: "play.circle",
                action: actions.startNextPomodoroPeriod
            )
            BubbleButton("Stop Pomodoro", systemImage: "stop.circle", action: actions.stopTimer)
        }
        .frame(width: 190)
    }

    private var timerControlsMenu: some View {
        VStack(spacing: 6) {
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
        }
        .frame(width: 190)
    }

    private var timerMenu: some View {
        BubbleTimerPage(
            onStart: actions.startTimer,
            onStartPomodoro: actions.startPomodoro,
            onStartStopwatch: actions.startStopwatch,
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
            .bubbleNumberBoxStyle(width: width, fontSize: fontSize)
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
struct BubbleTabs<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(Value, String)]
    /// Stacks the tabs top to bottom (like AM over PM), each filling the height it's given.
    var vertical = false

    var body: some View {
        let layout = vertical ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
        layout {
            ForEach(options, id: \.0) { value, title in
                let selected = value == selection
                Button {
                    selection = value
                } label: {
                    Text(title)
                        .font(.system(size: vertical ? 11 : 12, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8) // three tabs share a narrow bubble
                        .foregroundStyle(selected ? Color.white : .black)
                        .padding(.horizontal, vertical ? 7 : 4)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, vertical ? 2 : 5)
                        .frame(maxHeight: vertical ? .infinity : nil)
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

    /// A big, bold, centered number box, like the Timer's minutes.
    func bubbleNumberBoxStyle(width: CGFloat, fontSize: CGFloat) -> some View {
        textFieldStyle(.plain)
            .font(.system(size: fontSize, weight: .bold, design: .rounded).monospacedDigit())
            .multilineTextAlignment(.center)
            .frame(width: width)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 7).fill(.white))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(.black, lineWidth: 1.5))
    }
}

/// The small ‹ and ✕ in a page's header.
struct HeaderIconButton: View {
    let systemImage: String
    let help: String
    /// Narrower for steppers packed side by side.
    var width: CGFloat = 22
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .bold))
                .frame(width: width, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(HeaderIconButtonStyle())
        .help(help)
    }
}

private struct HeaderIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.black)
            .background(Circle().fill(configuration.isPressed ? Color.black.opacity(0.12) : .clear))
    }
}

/// A square icon-and-label button for the main menu grid, with an optional count badge.
struct MenuTile: View {
    static let width: CGFloat = 62

    let title: String
    let systemImage: String
    var badge = 0
    var monospacedLabel = false
    let action: () -> Void

    init(
        _ title: String,
        systemImage: String,
        badge: Int = 0,
        monospacedLabel: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.badge = badge
        self.monospacedLabel = monospacedLabel
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .semibold))
                    .frame(height: 20)
                Text(title)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: Self.width, height: 54)
            .contentShape(Rectangle())
        }
        .buttonStyle(TileButtonStyle())
        .overlay(alignment: .topTrailing) {
            if badge > 0 {
                Text("\(badge)")
                    .font(.system(size: 9, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .frame(minWidth: 16, minHeight: 16)
                    .background(Capsule().fill(.black))
                    .offset(x: 4, y: -4)
                    .allowsHitTesting(false)
            }
        }
    }
}

private struct TileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 9)
        configuration.label
            .foregroundStyle(.black)
            .background(shape.fill(configuration.isPressed ? Color.black.opacity(0.12) : .white))
            .overlay(shape.stroke(.black, lineWidth: 1.5))
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
struct CaretStepper: View {
    var canIncrement: Bool
    var canDecrement: Bool
    var increment: () -> Void
    var decrement: () -> Void
    /// Holding a caret keeps counting. Off for things like reordering, where one step per click is right.
    var repeatsWhenHeld = true
    /// Boxed carets (like a number input's), or bare narrow arrows.
    var outlined = true

    var body: some View {
        VStack(spacing: 2) {
            caret("chevron.up", enabled: canIncrement, action: increment)
            caret("chevron.down", enabled: canDecrement, action: decrement)
        }
        .buttonRepeatBehavior(repeatsWhenHeld ? .enabled : .disabled)
    }

    private func caret(_ systemImage: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: outlined ? 8 : 10, weight: .heavy))
                .frame(width: outlined ? 20 : 12, height: outlined ? 13 : 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(CaretButtonStyle(outlined: outlined))
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
    }
}

private struct CaretButtonStyle: ButtonStyle {
    var outlined: Bool

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 4)
        configuration.label
            .foregroundStyle(.black)
            .background(shape.fill(configuration.isPressed ? Color.black.opacity(0.12) : outlined ? .white : .clear))
            .overlay(shape.stroke(outlined ? Color.black : .clear, lineWidth: 1.5))
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
