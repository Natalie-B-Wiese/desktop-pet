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
    private(set) var isPetVisible = false
    private(set) var launchesAtLogin = SMAppService.mainApp.status == .enabled

    @ObservationIgnored private var petPanel: PetPanel?
    @ObservationIgnored private var bubble: SpeechBubbleController?
    @ObservationIgnored private var customizeWindow: NSWindow?
    @ObservationIgnored private var setTimerWindow: NSWindow?
    @ObservationIgnored private var remindersWindow: NSWindow?

    private static let visibleKey = "petVisible"

    private init() {
        settings.onChange = { [weak self] in self?.refreshPetImage() }
        settings.onScaleChange = { [weak self] in
            guard let self else { return }
            petPanel?.setScale(CGFloat(settings.scale))
        }
        timer.onStateChange = { [weak self] in self?.timerStateChanged() }
        reminders.onChange = { [weak self] in self?.remindersChanged() }
    }

    func start() {
        let panel = PetPanel(image: PetRenderer.render(settings.palette), scale: CGFloat(settings.scale))
        panel.menuProvider = { [weak self] in self?.makePetMenu() ?? NSMenu() }
        petPanel = panel
        let bubble = SpeechBubbleController(
            timer: timer, reminders: reminders, todos: todos, settings: settings, pet: panel, actions: BubbleActions(
            startTimer: { [weak self] duration, label in self?.startTimer(duration: duration, label: label) },
            startPomodoro: { [weak self] work, rest in
                self?.timer.startPomodoro(workLength: work, breakLength: rest)
            },
            startStopwatch: { [weak self] label in self?.timer.startStopwatch(label: label) },
            stopTimer: { [weak self] in self?.timer.stop() },
            togglePause: { [weak self] in self?.timer.togglePause() },
            startNextPomodoroPeriod: { [weak self] in self?.timer.startNextPomodoroPeriod() },
            customize: { [weak self] in self?.showCustomizeWindow() },
            hide: { [weak self] in self?.setPetVisible(false) },
            openRemindersWindow: { [weak self] in self?.showRemindersWindow() }
        ))
        panel.onClick = { [weak bubble] in bubble?.toggleMenu() }
        self.bubble = bubble

        let wasVisible = UserDefaults.standard.object(forKey: Self.visibleKey) as? Bool ?? true
        setPetVisible(wasVisible)
        remindersChanged() // show any reminders that came due while the app was closed

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
        petPanel?.setImage(PetRenderer.render(settings.palette))
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
        menu.addItem(ClosureMenuItem("Reminders…") { [weak self] in self?.showRemindersWindow() })
        menu.addItem(ClosureMenuItem("Customize…") { [weak self] in self?.showCustomizeWindow() })
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

    // MARK: - To-dos

    /// Shows the cat (if hidden) with its bubble open on the to-do list.
    func showTodos() {
        if !isPetVisible { setPetVisible(true) }
        bubble?.open(.todos)
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

    func showRemindersWindow() {
        if remindersWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(
                rootView: RemindersView(store: reminders)
            ))
            window.title = "Reminders"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            remindersWindow = window
        }
        NSApp.activate()
        remindersWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Customize

    func showCustomizeWindow() {
        if customizeWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(
                rootView: CustomizeView(settings: settings)
            ))
            window.title = "Customize Pet"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            customizeWindow = window
        }
        NSApp.activate()
        customizeWindow?.makeKeyAndOrderFront(nil)
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
    /// `--customize`, `--set-timer` or `--reminders` opens that window; `--timer <seconds>` starts a timer (add `--label <text>` and/or `--pause`);
    /// `--pomodoro <workSeconds> <breakSeconds>` starts Pomodoro mode; `--flip-start-mode` switches the Start page tab;
    /// `--stopwatch` starts a stopwatch (add `--label <text>`);
    /// `--menu [start|controls|reminders|add-reminder|todos|math]` opens the cat's click menu (on that page);
    /// `--snapshot <path.png>` saves a picture of each open app window as <path>-<n>.png after 1.5s.
    private func handleTestingArguments() {
        let args = ProcessInfo.processInfo.arguments
        func value(after flag: String) -> String? {
            args.firstIndex(of: flag).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
        }

        if args.contains("--customize") { showCustomizeWindow() }
        if args.contains("--set-timer") { showSetTimerWindow() }
        if args.contains("--reminders") { showRemindersWindow() }
        if let i = args.firstIndex(of: "--pomodoro"), i + 2 < args.count,
           let work = TimeInterval(args[i + 1]), let rest = TimeInterval(args[i + 2]) {
            timer.startPomodoro(workLength: work, breakLength: rest)
        }
        if args.contains("--stopwatch") { timer.startStopwatch(label: value(after: "--label")) }
        if let seconds = value(after: "--timer").flatMap(TimeInterval.init) {
            startTimer(duration: seconds, label: value(after: "--label"))
        }
        if args.contains("--pause") { timer.pause() }
        if args.contains("--menu") {
            bubble?.menu.page = switch value(after: "--menu") {
            case "start": .startTimer
            case "controls": .timerControls
            case "reminders": .reminders
            case "add-reminder": .addReminder
            case "todos": .todos
            case "math": .math
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
        if let path = value(after: "--snapshot") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
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
