import AppKit
import Observation
import ServiceManagement
import SwiftUI

/// Owns the floating pet, its speech bubble, the timer, and the app's windows.
@Observable
final class AppController {
    static let shared = AppController()

    let settings = PetSettings()
    let timer = PetTimer()
    let reminders = ReminderStore()
    let todos = TodoStore()
    let greetings = GreetingStore()
    let clipboard = ClipboardHistory()
    let notes = NoteStore()
    private(set) var isPetVisible = false
    private(set) var launchesAtLogin = SMAppService.mainApp.status == .enabled

    @ObservationIgnored private var petPanel: PetPanel?
    @ObservationIgnored private var bubble: SpeechBubbleController?
    @ObservationIgnored private var setTimerWindow: NSWindow?

    private static let visibleKey = "petVisible"

    private init() {
        settings.onChange = { [weak self] in self?.refreshPetImage() }
        settings.onScaleChange = { [weak self] in
            guard let self else { return }
            petPanel?.setScale(CGFloat(settings.scale))
        }
        timer.onStateChange = { [weak self] in self?.timerStateChanged() }
        reminders.onChange = { [weak self] in self?.remindersChanged() }
        greetings.onChange = { [weak self] in self?.greetingChanged() }
    }

    func start() {
        let panel = PetPanel(image: PetRenderer.render(settings.character, settings.palette), scale: CGFloat(settings.scale))
        panel.menuProvider = { [weak self] in self?.makePetMenu() ?? NSMenu() }
        petPanel = panel
        let bubble = SpeechBubbleController(
            timer: timer, reminders: reminders, todos: todos, greetings: greetings, notes: notes, clipboard: clipboard,
            settings: settings, pet: panel, actions: BubbleActions(
            startTimer: { [weak self] duration, label in self?.startTimer(duration: duration, label: label) },
            startPomodoro: { [weak self] work, rest in
                self?.timer.startPomodoro(workLength: work, breakLength: rest)
            },
            startStopwatch: { [weak self] label in self?.timer.startStopwatch(label: label) },
            stopTimer: { [weak self] in self?.timer.stop() },
            togglePause: { [weak self] in self?.timer.togglePause() },
            startNextPomodoroPeriod: { [weak self] in self?.timer.startNextPomodoroPeriod() },
            hide: { [weak self] in self?.setPetVisible(false) },
            takeScreenshot: { [weak self] in self?.takeScreenshot() },
            pickColor: { [weak self] in self?.pickColor() }
        ))
        panel.onClick = { [weak bubble] in bubble?.toggleMenu() }
        self.bubble = bubble

        let wasVisible = UserDefaults.standard.object(forKey: Self.visibleKey) as? Bool ?? true
        setPetVisible(wasVisible)
        remindersChanged() // show any reminders that came due while the app was closed
        startMorningCheck()

        handleTestingArguments()
    }

    // MARK: - Pet

    func togglePet() {
        setPetVisible(!isPetVisible)
    }

    func setPetVisible(_ visible: Bool) {
        isPetVisible = visible
        UserDefaults.standard.set(visible, forKey: Self.visibleKey)
        if visible {
            petPanel?.orderFrontRegardless()
        } else {
            bubble?.menu.page = nil
            petPanel?.orderOut(nil)
        }
        bubble?.update()
    }

    private func refreshPetImage() {
        petPanel?.setImage(PetRenderer.render(settings.character, settings.palette))
    }

    /// The cat's right-click menu.
    private func makePetMenu() -> NSMenu {
        let menu = NSMenu()
        let timerItem = NSMenuItem(title: "Start Timer", action: nil, keyEquivalent: "")
        let timerMenu = NSMenu()
        for minutes in PetTimer.presetMinutes {
            timerMenu.addItem(ClosureMenuItem(Self.presetTitle(minutes)) { [weak self] in
                self?.startTimer(minutes: minutes)
            })
        }
        timerMenu.addItem(.separator())
        timerMenu.addItem(ClosureMenuItem("Custom…") { [weak self] in self?.showSetTimerWindow() })
        timerItem.submenu = timerMenu
        if !timer.isBusy { // stop the current timer first
            menu.addItem(timerItem)
            menu.addItem(ClosureMenuItem(startPomodoroTitle) { [weak self] in self?.startPomodoro() })
            menu.addItem(ClosureMenuItem("Start Stopwatch") { [weak self] in self?.timer.startStopwatch() })
        }
        if let title = timer.nextPomodoroPeriodTitle {
            menu.addItem(ClosureMenuItem(title) { [weak self] in self?.timer.startNextPomodoroPeriod() })
        }
        if timer.hasCountdown {
            menu.addItem(ClosureMenuItem(timer.pauseTitle) { [weak self] in self?.timer.togglePause() })
        }
        if timer.hasCountdown && !timer.isStopwatch {
            let editItem = NSMenuItem(title: "Edit Timer", action: nil, keyEquivalent: "")
            let editMenu = NSMenu()
            editMenu.autoenablesItems = false
            for step in Self.editMenuSteps {
                let item = ClosureMenuItem(PetTimer.editTitle(step)) { [weak self] in
                    self?.timer.adjust(bySeconds: step)
                }
                item.isEnabled = timer.canAdjust(bySeconds: step)
                editMenu.addItem(item)
            }
            editItem.submenu = editMenu
            menu.addItem(editItem)
        }
        if timer.isActive {
            menu.addItem(ClosureMenuItem(timer.stopTitle) { [weak self] in self?.timer.stop() })
        }
        menu.addItem(.separator())
        menu.addItem(ClosureMenuItem("To-dos") { [weak self] in self?.showTodos() })
        menu.addItem(ClosureMenuItem("Notes") { [weak self] in self?.showPage(.notes) })
        menu.addItem(ClosureMenuItem("Take Screenshot") { [weak self] in self?.takeScreenshot() })
        menu.addItem(ClosureMenuItem("Reminders") { [weak self] in self?.showPage(.reminders) })
        menu.addItem(ClosureMenuItem("Customize") { [weak self] in self?.showCustomize() })
        menu.addItem(ClosureMenuItem("Hide Pet") { [weak self] in self?.setPetVisible(false) })
        return menu
    }

    // MARK: - Timer

    /// The Edit Timer submenu order: additions first, then subtractions.
    static let editMenuSteps = [30, 300, -30, -300]

    static func presetTitle(_ minutes: Int) -> String {
        minutes == 1 ? "1 minute" : "\(minutes) minutes"
    }

    func startTimer(minutes: Int) {
        startTimer(duration: TimeInterval(minutes * 60))
    }

    func startTimer(duration: TimeInterval, label: String? = nil) {
        timer.start(duration: duration, label: label)
    }

    /// Starts Pomodoro with the work and break lengths last used on the bubble's Start page.
    func startPomodoro() {
        let (work, rest) = savedPomodoroMinutes
        timer.startPomodoro(workLength: TimeInterval(work * 60), breakLength: TimeInterval(rest * 60))
    }

    /// "Start Pomodoro (25 / 5 min)".
    var startPomodoroTitle: String {
        let (work, rest) = savedPomodoroMinutes
        return "Start Pomodoro (\(work) / \(rest) min)"
    }

    private var savedPomodoroMinutes: (work: Int, rest: Int) {
        let defaults = UserDefaults.standard
        let work = defaults.object(forKey: TimerDraft.pomodoroWorkKey) as? Int ?? TimerDraft.defaultWorkMinutes
        let rest = defaults.object(forKey: TimerDraft.pomodoroBreakKey) as? Int ?? TimerDraft.defaultBreakMinutes
        return (work, rest)
    }

    private func timerStateChanged() {
        // The bubble needs the cat, so bring it back when a timer starts or finishes.
        if timer.isActive && !isPetVisible {
            setPetVisible(true)
        } else {
            bubble?.update()
        }
        if timer.state == .finished { petPanel?.hop() } // time's up, or a Pomodoro period ended
    }

    func showSetTimerWindow() {
        if setTimerWindow == nil {
            let view = SetTimerView(
                onStart: { [weak self] duration, label in
                    self?.setTimerWindow?.close()
                    self?.startTimer(duration: duration, label: label)
                },
                onCancel: { [weak self] in self?.setTimerWindow?.close() }
            )
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Set Timer"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            setTimerWindow = window
        }
        NSApp.activate()
        setTimerWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Screenshots

    @ObservationIgnored private var isTakingScreenshot = false

    /// Lets you select part of the screen with the standard macOS crosshair (Space picks a window,
    /// Esc cancels). The clipping goes on the clipboard, so clipboard history saves it as a slot.
    func takeScreenshot() {
        guard !isTakingScreenshot else { return }

        // The crosshair only sees other apps' windows with Screen Recording permission.
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess() // shows macOS's prompt, and lists the app in System Settings
            clipboard.screenshotNeedsPermission = true
            if !isPetVisible { setPetVisible(true) }
            bubble?.open(.clipboard)
            return
        }
        clipboard.screenshotNeedsPermission = false
        isTakingScreenshot = true

        // Get the cat and its bubble out of the way while you select.
        bubble?.menu.page = nil
        petPanel?.orderOut(nil)
        bubble?.update()

        let changeCountBefore = NSPasteboard.general.changeCount
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-c"] // interactive, copy to clipboard
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.screenshotFinished(changeCountBefore: changeCountBefore) }
        }
        // A moment for the cat to disappear before the crosshair appears.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            do {
                try process.run()
            } catch {
                NSLog("Couldn't start screencapture: \(error)")
                self?.screenshotFinished(changeCountBefore: changeCountBefore)
            }
        }
    }

    private func screenshotFinished(changeCountBefore: Int) {
        isTakingScreenshot = false
        if isPetVisible { petPanel?.orderFrontRegardless() }
        bubble?.update()

        // Cancelled with Esc: nothing new on the clipboard, so just come back.
        guard NSPasteboard.general.changeCount != changeCountBefore else { return }
        // Give clipboard history a moment to save it, then show it in the top slot.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
            guard let self else { return }
            if !isPetVisible { setPetVisible(true) }
            bubble?.open(.clipboard)
        }
    }

    // MARK: - Color picker

    @ObservationIgnored private var colorSampler: NSColorSampler?

    /// Shows macOS's magnifier to pick a color from anywhere on screen (Esc cancels).
    /// Its hex ("#E8893A") goes on the clipboard, so clipboard history saves it as a slot.
    func pickColor() {
        guard colorSampler == nil else { return }
        // A moment for the bubble to close before the magnifier appears.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }
            let sampler = NSColorSampler()
            colorSampler = sampler
            sampler.show { [weak self] color in
                guard let self else { return }
                colorSampler = nil
                guard let color else {
                    showPage(.clipboard) // cancelled: just come back
                    return
                }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("#\(color.hexString)", forType: .string)
                // Give clipboard history a moment to save it, then show it in the top slot.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
                    self?.showPage(.clipboard)
                }
            }
        }
    }

    // MARK: - To-dos

    /// Shows the cat (if hidden) with its bubble open on the to-do list.
    func showTodos() {
        showPage(.todos)
    }

    /// Shows the cat (if hidden) with its bubble open on `page`.
    func showPage(_ page: BubbleMenu.Page) {
        if !isPetVisible { setPetVisible(true) }
        bubble?.open(page)
    }

    // MARK: - Reminders

    @ObservationIgnored private var lastDueCount = 0

    private func remindersChanged() {
        // A due reminder needs the cat to be seen, so bring it back.
        if !reminders.due.isEmpty && !isPetVisible {
            setPetVisible(true)
        } else {
            bubble?.update()
        }
        // Hop only when a new reminder arrives, not when one is closed or deleted.
        if reminders.due.count > lastDueCount { petPanel?.hop() }
        lastDueCount = reminders.due.count
    }


    // MARK: - Morning check: daily meeting pull and greeting

    @ObservationIgnored private var morningObservers: [NSObjectProtocol] = []
    @ObservationIgnored private var isRunningMorningCheck = false

    /// Once a day, pulls today's meetings and then greets you. Checks at launch, when the Mac wakes or
    /// the screen unlocks (for a Mac left awake overnight), and at midnight if it's awake then.
    private func startMorningCheck() {
        runMorningCheck()
        // Waits a little after waking so the Calendar app can sync any overnight changes from Google first.
        morningObservers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { self?.runMorningCheck() }
        })
        morningObservers.append(DistributedNotificationCenter.default().addObserver(
            forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { self?.runMorningCheck() }
        })
        morningObservers.append(NotificationCenter.default.addObserver(
            forName: .NSCalendarDayChanged, object: nil, queue: .main
        ) { [weak self] _ in self?.runMorningCheck() })
    }

    /// The pull goes first, so the greeting sees today's meetings. Wake and unlock often come together,
    /// so a second check waits for the first instead of greeting twice.
    private func runMorningCheck() {
        guard !isRunningMorningCheck else { return }
        isRunningMorningCheck = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            await pullMeetingsIfNewDay()
            await greetIfNewDay()
            isRunningMorningCheck = false
        }
    }

    /// Only when Calendar access is already on (so it never shows the permission dialog by itself)
    /// and meetings haven't been pulled today, by this or by the Pull meetings button.
    @MainActor
    private func pullMeetingsIfNewDay() async {
        guard CalendarMeetings.hasAccess, !reminders.pulledMeetingsToday,
              let meetings = try? await CalendarMeetings.todaysUpcoming() else { return }
        reminders.syncMeetings(meetings)
    }

    /// The first check of the day from 4 AM on, unless turned off in Settings.
    @MainActor
    private func greetIfNewDay() async {
        guard AppPreferences.showsMorningGreeting, !greetings.shownToday,
              Calendar.current.component(.hour, from: Date()) >= MorningGreeting.earliestHour else { return }
        greetings.show(await makeGreeting())
    }

    @MainActor
    private func makeGreeting() async -> MorningGreeting {
        // `hasAccess` first, so the greeting never asks for Calendar access.
        let meetings = CalendarMeetings.hasAccess ? try? await CalendarMeetings.todaysUpcoming() : nil
        return MorningGreeting(date: Date(), meetings: meetings, allDayEvents: CalendarMeetings.todaysAllDayEvents())
    }

    private func greetingChanged() {
        // Like a reminder, the greeting brings the cat back, and she hops to say hi.
        if greetings.current != nil && !isPetVisible {
            setPetVisible(true)
        } else {
            bubble?.update()
        }
        if greetings.current != nil { petPanel?.hop() }
    }

    // MARK: - Customize

    /// Customize lives in the bubble: name, color swatches and size, with Topsy as the preview.
    func showCustomize() {
        showPage(.customize)
    }

    // MARK: - Launch at Login

    func setLaunchesAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Launch at Login change failed: \(error)")
        }
        launchesAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: - Testing

    /// Launch arguments that let Claude check windows without screen-recording permission:
    /// `--customize` opens that bubble page; `--set-timer` opens that window; `--timer <seconds>` starts a timer (add `--label <text>` and/or `--pause`);
    /// `--pomodoro <workSeconds> <breakSeconds>` starts Pomodoro mode; `--flip-start-mode` switches the Start page tab;
    /// `--stopwatch` starts a stopwatch (add `--label <text>`);
    /// `--greeting` shows the morning greeting now, without using up today's real one;
    /// `--menu [start|controls|reminders|add-reminder|edit-reminder|todos|math|clipboard|notes|settings]` opens the cat's click menu (on that page);
    /// `--convert-input <amount>` fills in the Math page's Convert tab;
    /// `--type <text>` types that text into the focused window after 1s, a key every 0.1s ("⌫" is Backspace);
    /// `--snapshot <path.png>` saves a picture of each open app window as <path>-<n>.png after 1.5s (plus any typing time).
    private func handleTestingArguments() {
        let args = ProcessInfo.processInfo.arguments
        func value(after flag: String) -> String? {
            args.firstIndex(of: flag).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
        }

        if args.contains("--customize") { showCustomize() }
        if args.contains("--set-timer") { showSetTimerWindow() }
        if let i = args.firstIndex(of: "--pomodoro"), i + 2 < args.count,
           let work = TimeInterval(args[i + 1]), let rest = TimeInterval(args[i + 2]) {
            timer.startPomodoro(workLength: work, breakLength: rest)
        }
        if args.contains("--stopwatch") { timer.startStopwatch(label: value(after: "--label")) }
        if let seconds = value(after: "--timer").flatMap(TimeInterval.init) {
            startTimer(duration: seconds, label: value(after: "--label"))
        }
        if args.contains("--pause") { timer.pause() }
        if args.contains("--greeting") {
            Task { @MainActor [weak self] in
                guard let self else { return }
                greetings.show(await makeGreeting(), remember: false)
            }
        }
        if args.contains("--menu") {
            bubble?.menu.page = switch value(after: "--menu") {
            case "start": .startTimer
            case "controls": .timerControls
            case "reminders": .reminders
            case "add-reminder": .addReminder
            case "edit-reminder": reminders.upcoming.first(where: { $0.meetingID == nil }).map { .editReminder($0.id) } ?? .reminders
            case "todos": .todos
            case "math": .math
            case "clipboard": .clipboard
            case "notes": .notes
            case "settings": .settings
            default: .main
            }
        }

        if args.contains("--flip-start-mode") {
            // Switches the Start page between Timer and Pomodoro after a second, as a click would.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                let defaults = UserDefaults.standard
                let current = defaults.string(forKey: "startPage.mode") ?? "timer"
                defaults.set(current == "timer" ? "pomodoro" : "timer", forKey: "startPage.mode")
            }
        }
        if let text = value(after: "--type") {
            for (n, character) in text.enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1 + 0.1 * Double(n)) {
                    guard let window = NSApp.keyWindow else { return }
                    let isBackspace = character == "⌫"
                    let characters = isBackspace ? "\u{7F}" : String(character)
                    for type in [NSEvent.EventType.keyDown, .keyUp] {
                        guard let event = NSEvent.keyEvent(
                            with: type, location: .zero, modifierFlags: [], timestamp: 0,
                            windowNumber: window.windowNumber, context: nil,
                            characters: characters, charactersIgnoringModifiers: characters,
                            isARepeat: false, keyCode: isBackspace ? 51 : 0
                        ) else { continue }
                        NSApp.postEvent(event, atStart: false)
                    }
                }
            }
        }
        if let path = value(after: "--snapshot") {
            // Waits for any `--type` keys to finish first.
            let typingTime = 0.1 * Double(value(after: "--type")?.count ?? 0)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5 + typingTime) {
                let base = (path as NSString).deletingPathExtension
                for (n, window) in NSApp.windows.filter(\.isVisible).enumerated() {
                    guard let view = window.contentView?.superview ?? window.contentView,
                          let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                    view.cacheDisplay(in: view.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?
                        .write(to: URL(fileURLWithPath: "\(base)-\(n).png"))
                }
            }
        }
    }
}
