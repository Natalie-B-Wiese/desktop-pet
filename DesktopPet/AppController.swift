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
    private(set) var isPetVisible = false
    private(set) var launchesAtLogin = SMAppService.mainApp.status == .enabled

    @ObservationIgnored private var petPanel: PetPanel?
    @ObservationIgnored private var bubble: SpeechBubbleController?
    @ObservationIgnored private var customizeWindow: NSWindow?
    @ObservationIgnored private var setTimerWindow: NSWindow?

    private static let visibleKey = "petVisible"

    private init() {
        settings.onChange = { [weak self] in self?.refreshPetImage() }
        settings.onScaleChange = { [weak self] in
            guard let self else { return }
            petPanel?.setScale(CGFloat(settings.scale))
        }
        timer.onStateChange = { [weak self] in self?.timerStateChanged() }
    }

    func start() {
        let panel = PetPanel(image: PetRenderer.render(settings.palette), scale: CGFloat(settings.scale))
        panel.menuProvider = { [weak self] in self?.makePetMenu() ?? NSMenu() }
        petPanel = panel
        let bubble = SpeechBubbleController(timer: timer, pet: panel, actions: BubbleActions(
            startTimer: { [weak self] duration in self?.startTimer(duration: duration) },
            stopTimer: { [weak self] in self?.timer.stop() },
            togglePause: { [weak self] in self?.timer.togglePause() },
            customize: { [weak self] in self?.showCustomizeWindow() },
            hide: { [weak self] in self?.setPetVisible(false) }
        ))
        panel.onClick = { [weak bubble] in bubble?.toggleMenu() }
        self.bubble = bubble

        let wasVisible = UserDefaults.standard.object(forKey: Self.visibleKey) as? Bool ?? true
        setPetVisible(wasVisible)

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
        if !timer.hasCountdown { menu.addItem(timerItem) } // stop the current timer first
        if timer.hasCountdown {
            menu.addItem(ClosureMenuItem(timer.pauseTitle) { [weak self] in self?.timer.togglePause() })
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
            menu.addItem(ClosureMenuItem("Stop Timer") { [weak self] in self?.timer.stop() })
        }
        menu.addItem(.separator())
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

    func startTimer(duration: TimeInterval) {
        timer.start(duration: duration)
    }

    private func timerStateChanged() {
        // The bubble needs the cat, so bring it back when a timer starts or finishes.
        if timer.isActive && !isPetVisible {
            setPetVisible(true)
        } else {
            bubble?.update()
        }
    }

    func showSetTimerWindow() {
        if setTimerWindow == nil {
            let view = SetTimerView(
                onStart: { [weak self] duration in
                    self?.setTimerWindow?.close()
                    self?.startTimer(duration: duration)
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
    /// `--customize` or `--set-timer` opens that window; `--timer <seconds>` starts a timer (add `--pause` to pause it);
    /// `--menu` or `--menu timer` opens the cat's click menu (on that page);
    /// `--snapshot <path.png>` saves a picture of each open app window as <path>-<n>.png after 1.5s.
    private func handleTestingArguments() {
        let args = ProcessInfo.processInfo.arguments
        func value(after flag: String) -> String? {
            args.firstIndex(of: flag).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
        }

        if args.contains("--customize") { showCustomizeWindow() }
        if args.contains("--set-timer") { showSetTimerWindow() }
        if let seconds = value(after: "--timer").flatMap(TimeInterval.init) { startTimer(duration: seconds) }
        if args.contains("--pause") { timer.pause() }
        if args.contains("--menu") {
            bubble?.menu.page = switch value(after: "--menu") {
            case "timer": .timer
            case "edit": .editTimer
            default: .main
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
