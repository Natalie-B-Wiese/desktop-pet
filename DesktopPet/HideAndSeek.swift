import AppKit
import Observation

/// Hide and Seek: Topsy hides in one of your open apps. Switching to that app shows her peeking up from the
/// bottom of its window (she ducks again if you switch away), and clicking her finds her; then she goes home.
/// Only app names and window positions are used (no permission needed), and only while a round is on; nothing is saved.
@Observable
final class HideAndSeek {
    enum Ending {
        case found(seconds: Int)
        /// You gave up, or she did after `timeLimit`. `app` is where she was hiding.
        case gaveUp(app: String?)
        /// A reminder, timer or greeting needs her at home.
        case interrupted
    }

    /// Hiding, peeking, or just found. She's away from her spot the whole time.
    private(set) var isPlaying = false
    /// Peeking out of the app she hid in, waiting to be clicked.
    @ObservationIgnored private(set) var isPeeking = false
    /// Why she couldn't hide, shown on the page.
    private(set) var problem: String?

    /// She leaves her spot.
    @ObservationIgnored var onHide: () -> Void = {}
    /// She peeks up from the bottom of that window (in screen coordinates), `along` (0–1) the way across it.
    @ObservationIgnored var onPeek: (_ window: NSRect, _ along: CGFloat) -> Void = { _, _ in }
    /// You switched away from her app, so she ducks out of sight again.
    @ObservationIgnored var onDuck: () -> Void = {}
    /// You clicked her: she comes all the way out.
    @ObservationIgnored var onFound: () -> Void = {}
    /// She's back home.
    @ObservationIgnored var onEnd: (Ending) -> Void = { _ in }

    /// She gives up on you after this long.
    static let timeLimit: TimeInterval = 120
    /// How long she stays out after being found, before going home.
    private static let foundTime: TimeInterval = 1.5

    @ObservationIgnored private var hidingIn: pid_t?
    /// Where along the window's bottom she peeks, the same all round.
    @ObservationIgnored private var along: CGFloat = 0.5
    @ObservationIgnored private var startedAt = Date()
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var giveUpTimer: Timer?
    /// Counts rounds and peeks, so a step still coming from an earlier one is dropped.
    @ObservationIgnored private var step = 0

    /// Hides in an open app other than the one you're in. Says why on the page if there's none.
    /// `app` picks one by name, for testing.
    func start(in app: String? = nil) {
        guard !isPlaying else { return }
        let spots = Self.hidingSpots().filter { app == nil || NSRunningApplication(processIdentifier: $0)?.localizedName == app }
        guard let app = spots.randomElement() else {
            problem = "Open another app first, so I have somewhere to hide."
            return
        }
        problem = nil
        isPlaying = true
        step += 1
        startedAt = Date()
        hidingIn = app
        along = .random(in: 0.1...0.9)
        let center = NSWorkspace.shared.notificationCenter
        observers = [
            center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard let self, let app else { return }
                if app.processIdentifier == hidingIn { peek() } else { duck() }
            },
            // Her hiding spot closed: she moves to another app, or gives up if there's none.
            center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                guard let self, let app, app.processIdentifier == hidingIn else { return }
                duck()
                if let next = Self.hidingSpots().randomElement() { hidingIn = next } else { end(.gaveUp(app: nil)) }
            },
        ]
        giveUpTimer = Timer.scheduledTimer(withTimeInterval: Self.timeLimit, repeats: false) { [weak self] _ in
            self?.giveUp()
        }
        onHide()
    }

    func giveUp() {
        guard isPlaying else { return }
        end(.gaveUp(app: hidingIn.flatMap { NSRunningApplication(processIdentifier: $0)?.localizedName }))
    }

    /// Brings her home right away, with no line (something else needs her).
    func interrupt() {
        if isPlaying { end(.interrupted) }
    }

    /// The problem line goes away when you leave the page.
    func clearProblem() {
        problem = nil
    }

    /// You clicked her while she peeked: found! She comes out, then goes home.
    func click() {
        guard isPeeking else { return }
        let seconds = max(1, Int(Date().timeIntervalSince(startedAt).rounded()))
        stopWatching()
        isPeeking = false
        step += 1
        let current = step
        onFound()
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.foundTime) { [weak self] in
            guard let self, step == current else { return }
            end(.found(seconds: seconds))
        }
    }

    /// Waits for the app's window to come to the front (and its Space to slide in), then peeks up from it.
    private func peek() {
        step += 1
        let current = step
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, step == current, let pid = hidingIn,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
                  let window = Self.frontWindow(of: pid) else { return }
            isPeeking = true
            onPeek(window, along)
        }
    }

    private func duck() {
        step += 1 // a peek still on its way is dropped
        guard isPeeking else { return }
        isPeeking = false
        onDuck()
    }

    private func end(_ ending: Ending) {
        stopWatching()
        step += 1
        isPlaying = false
        isPeeking = false
        onEnd(ending)
    }

    private func stopWatching() {
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        observers = []
        giveUpTimer?.invalidate()
        giveUpTimer = nil
        hidingIn = nil
    }

    // MARK: - Apps and windows

    /// Your open apps with a window showing on this Space, except the one you're in and this app.
    private static func hidingSpots() -> [pid_t] {
        let mine = ProcessInfo.processInfo.processIdentifier
        let current = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let withWindows = Set(windows().map(\.pid))
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && !$0.isHidden }
            .map(\.processIdentifier)
            .filter { $0 != mine && $0 != current && withWindows.contains($0) }
    }

    /// The app's frontmost window, in screen coordinates.
    private static func frontWindow(of pid: pid_t) -> NSRect? {
        windows().first { $0.pid == pid }?.frame
    }

    /// Normal app windows showing on screen, front to back. Their owners and positions need no permission
    /// (only their titles would).
    private static func windows() -> [(pid: pid_t, frame: NSRect)] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return [] }
        // Window bounds count down from the top of the main screen; AppKit counts up from its bottom.
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        return list.compactMap { info in
            guard info[kCGWindowLayer as String] as? Int == 0,
                  (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds),
                  rect.width >= 150, rect.height >= 100 else { return nil }
            return (pid, NSRect(x: rect.minX, y: mainHeight - rect.maxY, width: rect.width, height: rect.height))
        }
    }
}
