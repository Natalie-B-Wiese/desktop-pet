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
    let chatter = ChatterStore()
    let clipboard = ClipboardHistory()
    let notes = NoteStore()
    private(set) var isPetVisible = false
    private(set) var launchesAtLogin = SMAppService.mainApp.status == .enabled

    @ObservationIgnored private var petPanel: PetPanel?
    @ObservationIgnored private var bubble: SpeechBubbleController?
    @ObservationIgnored private var setTimerWindow: NSWindow?

    private static let visibleKey = "petVisible"

    private init() {
        AppPreferences.moveMeetingLeadToHeadsUp()
        reminders.applyHeadsUpChange() // the reminders loaded before the setting moved
        settings.onChange = { [weak self] in self?.refreshPetImage() }
        settings.onScaleChange = { [weak self] in
            guard let self else { return }
            petPanel?.setScale(CGFloat(settings.scale))
        }
        timer.onStateChange = { [weak self] in self?.timerStateChanged() }
        reminders.onChange = { [weak self] in self?.remindersChanged() }
        greetings.onChange = { [weak self] in self?.greetingChanged() }
        chatter.onChange = { [weak self] in self?.bubble?.update() }
        todos.onCheckedOff = { [weak self] allDone in self?.cheerTodo(allDone: allDone) }
    }

    func start() {
        let panel = PetPanel(image: PetRenderer.render(settings.character, settings.palette), scale: CGFloat(settings.scale))
        panel.menuProvider = { [weak self] in self?.makePetMenu() ?? NSMenu() }
        petPanel = panel
        let bubble = SpeechBubbleController(
            timer: timer, reminders: reminders, todos: todos, greetings: greetings, chatter: chatter, notes: notes,
            clipboard: clipboard, settings: settings, pet: panel, actions: BubbleActions(
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
        startChatter()

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
        if timer.isActive { chatter.line = nil } // the timer gets the bubble
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
            cheer(.screenshot)
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
                    self?.cheerColor(color)
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
    @ObservationIgnored private var lastHeadsUpKeys: Set<String> = []
    @ObservationIgnored private var lastDueKeys: Set<String> = []
    /// The hop takes about 0.6s; her line follows a beat after it.
    private static let headsUpLineDelay: TimeInterval = 2

    private func remindersChanged() {
        // A due reminder or a heads-up needs the cat to be seen, so bring it back.
        if (!reminders.due.isEmpty || !reminders.headsUp.isEmpty) && !isPetVisible {
            setPetVisible(true)
        } else {
            bubble?.update()
        }
        // Hop only when a new reminder or heads-up arrives, not when one is closed or deleted.
        let headsUpKeys = Set(reminders.headsUp.map(\.occurrenceKey))
        let newHeadsUp = reminders.headsUp.first { !lastHeadsUpKeys.contains($0.occurrenceKey) }
        if reminders.due.count > lastDueCount || newHeadsUp != nil { petPanel?.hop() }
        // Her personality's take goes beside her while the main bubble shows the reminder (nothing with Chatter on None).
        // It waits until the hop is over and a beat more, so the two bubbles don't pop up at once.
        // A reminder coming due wins over a heads-up arriving at the same moment.
        let newDue = reminders.due.first { !lastDueKeys.contains($0.occurrenceKey) }
        if let newDue, AppPreferences.chatter != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.headsUpLineDelay) { [weak self] in
                // Skipped if it was clicked away meanwhile.
                guard let self, let personality = AppPreferences.chatter,
                      reminders.due.contains(where: { $0.occurrenceKey == newDue.occurrenceKey }) else { return }
                chatter.sayAbovePage(Chatter.line(.reminderDue, personality))
            }
        } else if let newHeadsUp, AppPreferences.chatter != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.headsUpLineDelay) { [weak self] in
                // Skipped if the heads-up was clicked away (or came due) meanwhile.
                guard let self, let personality = AppPreferences.chatter,
                      reminders.headsUp.contains(where: { $0.occurrenceKey == newHeadsUp.occurrenceKey }) else { return }
                chatter.sayAbovePage(Chatter.line(.headsUp, personality))
            }
        }
        lastDueCount = reminders.due.count
        lastDueKeys = Set(reminders.due.map(\.occurrenceKey))
        lastHeadsUpKeys = headsUpKeys
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
        return MorningGreeting(
            date: Date(), meetings: meetings, allDayEvents: CalendarMeetings.todaysAllDayEvents()
        )
    }

    private func greetingChanged() {
        // Like a reminder, the greeting brings the cat back, and she hops to say hi.
        if greetings.current != nil && !isPetVisible {
            setPetVisible(true)
        } else {
            bubble?.update()
        }
        if greetings.current != nil { petPanel?.hop() }
        // Her hello goes beside her, after the hop like a heads-up's line (nothing with Chatter on None).
        if let greeting = greetings.current, AppPreferences.chatter != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.headsUpLineDelay) { [weak self] in
                // Skipped if it was clicked away meanwhile, or is waiting behind a reminder.
                guard let self, let personality = AppPreferences.chatter, greetings.current == greeting,
                      reminders.due.isEmpty, reminders.headsUp.isEmpty else { return }
                chatter.sayAbovePage(Chatter.greetingLine(personality, at: greeting.date))
            }
        }
    }

    // MARK: - Chatter

    @ObservationIgnored private var chatterClock: Timer?
    private static let lastLunchKey = "chatter.lastLunch"

    /// Checks the clock each minute, for lunch.
    private func startChatter() {
        chatterClock = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.checkChatterClock()
        }
    }

    /// Lunch at noon, once a day, like a pet with a routine (Natalie found 11:45 felt random). If you're away or busy
    /// then, she says it when you're back, until 12:30.
    private func checkChatterClock() {
        let now = Date()
        guard Self.secondsSinceInput < 120, !Self.isScreenLocked else { return }
        let defaults = UserDefaults.standard
        let calendar = Calendar.current
        let minute = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        if (12 * 60..<12 * 60 + 30).contains(minute),
           !((defaults.object(forKey: Self.lastLunchKey) as? Date).map(calendar.isDateInToday) ?? false),
           sayLunch() {
            defaults.set(now, forKey: Self.lastLunchKey)
        }
    }

    /// Lunch in the small bubble beside her, unless chatter is off, she's hidden, a meeting is on, or something else
    /// is being said (a reminder, the greeting, or another line beside her). Returns whether she said it, so she can try again.
    @discardableResult
    private func sayLunch(force: Bool = false) -> Bool {
        guard let personality = AppPreferences.chatter ?? (force ? .bubbly : nil) else { return false }
        if !force {
            guard isPetVisible, reminders.due.isEmpty, reminders.headsUp.isEmpty, greetings.current == nil,
                  chatter.pageLine == nil, !CalendarMeetings.isInMeeting() else { return false }
        }
        chatter.sayAbovePage(Chatter.line(.lunch, personality))
        return true
    }

    /// A cheer in the small bubble above the To-dos page, every time one is checked off.
    private func cheerTodo(allDone: Bool) {
        guard let personality = AppPreferences.chatter else { return }
        chatter.sayAbovePage(Chatter.line(allDone ? .allTodosDone : .todoChecked, personality))
    }

    /// A line in the small bubble beside her, right after something you did (no gap or meeting check, like to-do cheers).
    private func cheer(_ moment: ChatterMoment) {
        guard let personality = AppPreferences.chatter else { return }
        chatter.sayAbovePage(Chatter.line(moment, personality))
    }

    /// Names the color you picked, or notices it's one of hers (any part her current look uses; black and white never count).
    private func cheerColor(_ color: NSColor) {
        guard let personality = AppPreferences.chatter else { return }
        let palette = settings.palette
        let used = PetRenderer.usedSlots(for: settings.character)
        let hers = zip([palette.main, palette.secondary, palette.detail], used).filter(\.1).map(\.0)
        if hers.contains(where: { ColorNames.looksAlike($0, color) }) {
            chatter.sayAbovePage(Chatter.line(.ownColorPicked, personality))
        } else {
            chatter.sayAbovePage(Chatter.line(.colorPicked, personality, color: ColorNames.name(for: color)))
        }
    }

    private static var secondsSinceInput: TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    private static var isScreenLocked: Bool {
        (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool ?? false
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
    /// `--remind-in <seconds>` adds a one-time reminder due that many seconds from now (add `--label <text>`; it's saved, so back up first);
    /// `--greeting` shows the morning greeting now, without using up today's real one;
    /// `--menu [start|controls|reminders|add-reminder|edit-reminder|todos|math|clipboard|notes|settings]` opens the cat's click menu (on that page);
    /// `--chatter [lunch|todo|all-done|preview|screenshot|color|own-color]` says that line now (deck order is used up as normal; `color` is coral);
    /// `--convert-input <amount>` fills in the Math page's Convert tab;
    /// `--type <text>` types that text into the focused window after 1s, a key every 0.1s ("⌫" is Backspace);
    /// `--snapshot <path.png>` saves a picture of each open app window as <path>-<n>.png after 1.5s (or `--snapshot-delay <sec>`; plus any typing time),
    /// and all of them (minus the menu bar icon) placed as they are on screen as <path>.png.
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
        if let seconds = value(after: "--remind-in").flatMap(TimeInterval.init) {
            reminders.addForTesting(at: Date().addingTimeInterval(seconds), message: value(after: "--label"))
        }
        if args.contains("--greeting") {
            Task { @MainActor [weak self] in
                guard let self else { return }
                greetings.show(await makeGreeting(), remember: false)
            }
        }
        if let moment = value(after: "--chatter") {
            // Says a line now, skipping the usual checks; `todo`, `all-done` and `preview` need their page open; with Chatter on None, lines are Upbeat's.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self else { return }
                let personality = AppPreferences.chatter ?? .bubbly
                switch moment {
                case "todo": chatter.sayAbovePage(Chatter.line(.todoChecked, personality))
                case "all-done": chatter.sayAbovePage(Chatter.line(.allTodosDone, personality))
                case "preview": chatter.sayAbovePage(Chatter.line(.preview, personality))
                case "screenshot": cheer(.screenshot)
                case "color", "own-color":
                    // A coral pick, or her own body color.
                    cheerColor(moment == "color" ? NSColor(srgbRed: 1, green: 0.5, blue: 0.31, alpha: 1) : settings.palette.main)
                default: sayLunch(force: true)
                }
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
            let delay = value(after: "--snapshot-delay").flatMap(TimeInterval.init) ?? 1.5
            DispatchQueue.main.asyncAfter(deadline: .now() + delay + typingTime) {
                let base = (path as NSString).deletingPathExtension
                var pictures: [(frame: NSRect, rep: NSBitmapImageRep)] = []
                for (n, window) in NSApp.windows.filter(\.isVisible).enumerated() {
                    guard let view = window.contentView?.superview ?? window.contentView,
                          let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                    view.cacheDisplay(in: view.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?
                        .write(to: URL(fileURLWithPath: "\(base)-\(n).png"))
                    if window.level != .statusBar && !String(describing: type(of: window)).contains("StatusBar") {
                        pictures.append((window.frame, rep))
                    }
                }
                // Everything together, at 2x, laid out as on screen.
                let union = pictures.map(\.frame).reduce(NSRect.null) { $0.union($1) }
                guard !union.isNull, let canvas = NSBitmapImageRep(
                    bitmapDataPlanes: nil, pixelsWide: Int(union.width * 2), pixelsHigh: Int(union.height * 2),
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
                ) else { return }
                canvas.size = union.size
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: canvas)
                for picture in pictures {
                    // Blended, so a window's transparent edges don't erase the one under it.
                    picture.rep.draw(in: picture.frame.offsetBy(dx: -union.minX, dy: -union.minY), from: .zero,
                                     operation: .sourceOver, fraction: 1, respectFlipped: false, hints: nil)
                }
                NSGraphicsContext.restoreGraphicsState()
                try? canvas.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(base).png"))
            }
        }
    }
}
