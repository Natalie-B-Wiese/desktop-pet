import Foundation
import Observation

/// A countdown that ends at a fixed date, so it stays accurate across sleep.
@Observable
final class PetTimer {
    enum State: Equatable {
        case idle
        case running(end: Date)
        case paused(remaining: TimeInterval)
        case finished

        var isPaused: Bool {
            if case .paused = self { true } else { false }
        }
    }

    /// Work/break cycling. Each period ends in `.finished`, and the next starts when you click.
    struct Pomodoro: Equatable {
        enum Phase { case work, rest }

        var phase: Phase
        var workLength: TimeInterval
        var breakLength: TimeInterval
        /// Which work session this is (or the break follows), starting at 1.
        var session: Int

        var workMinutes: Int { Int((workLength / 60).rounded()) }
        var breakMinutes: Int { Int((breakLength / 60).rounded()) }
    }

    private(set) var state: State = .idle

    /// Set while Pomodoro mode is running, including between periods.
    private(set) var pomodoro: Pomodoro?

    /// A regular timer or Pomodoro that hasn't been stopped, so "Start" should stay hidden.
    var isBusy: Bool { hasCountdown || pomodoro != nil }

    /// Optional name for the current timer, like "Tea", exactly as typed.
    /// Kept through pause, resume and edits. Use `displayLabel` to show it.
    var label: String?

    /// What to show above the countdown: the Pomodoro period, or the trimmed label (nil if none).
    var displayLabel: String? {
        if let pomodoro {
            return pomodoro.phase == .work ? "Work" : "Break"
        }
        return label.flatMap(TimerDraft.cleanLabel)
    }

    @ObservationIgnored var onStateChange: (() -> Void)?
    @ObservationIgnored private var timer: Timer?

    static let presetMinutes = [1, 5, 10, 15, 25, 30, 45, 60]

    var isActive: Bool { state != .idle }

    /// Running or paused, i.e. a countdown that can be paused, resumed or stopped.
    var hasCountdown: Bool {
        switch state {
        case .running, .paused: true
        case .idle, .finished: false
        }
    }

    /// Time left on a running or paused countdown, otherwise nil.
    var remaining: TimeInterval? {
        switch state {
        case .running(let end): max(0, end.timeIntervalSinceNow)
        case .paused(let remaining): remaining
        case .idle, .finished: nil
        }
    }

    func start(duration: TimeInterval, label: String? = nil) {
        self.label = label
        pomodoro = nil
        schedule(end: Date().addingTimeInterval(duration))
    }

    /// Starts Pomodoro mode with its first work session.
    func startPomodoro(workLength: TimeInterval, breakLength: TimeInterval) {
        label = nil
        pomodoro = Pomodoro(phase: .work, workLength: workLength, breakLength: breakLength, session: 1)
        schedule(end: Date().addingTimeInterval(workLength))
    }

    /// After a Pomodoro period ends: starts the break, or the next work session.
    func startNextPomodoroPeriod() {
        guard var pomodoro, state == .finished else { return }
        if pomodoro.phase == .work {
            pomodoro.phase = .rest
        } else {
            pomodoro.phase = .work
            pomodoro.session += 1
        }
        self.pomodoro = pomodoro
        schedule(end: Date().addingTimeInterval(pomodoro.phase == .work ? pomodoro.workLength : pomodoro.breakLength))
    }

    /// "Start Break" or "Start Work Session", for the menus once a Pomodoro period ends.
    var nextPomodoroPeriodTitle: String? {
        guard let pomodoro, state == .finished else { return nil }
        return pomodoro.phase == .work ? "Start Break" : "Start Work Session"
    }

    /// "Stop Timer" or "Stop Pomodoro".
    var stopTitle: String { pomodoro == nil ? "Stop Timer" : "Stop Pomodoro" }

    /// The Edit timer buttons, in seconds, in the order they appear in the bubble.
    static let editSteps = [-300, -30, 30, 300]

    /// "−5m", "+30s": short labels for the bubble's buttons.
    static func shortEditTitle(_ seconds: Int) -> String {
        let sign = seconds > 0 ? "+" : "−"
        let amount = abs(seconds)
        return amount % 60 == 0 ? "\(sign)\(amount / 60)m" : "\(sign)\(amount)s"
    }

    /// "Add 30 Seconds", "Subtract 5 Minutes": labels for the menu bar and right-click menus.
    static func editTitle(_ seconds: Int) -> String {
        let verb = seconds > 0 ? "Add" : "Subtract"
        let amount = abs(seconds)
        let unit = amount % 60 == 0
            ? (amount == 60 ? "1 Minute" : "\(amount / 60) Minutes")
            : "\(amount) Seconds"
        return "\(verb) \(unit)"
    }

    /// Whether adding `seconds` (negative to subtract) would leave time on the clock.
    func canAdjust(bySeconds seconds: Int) -> Bool {
        guard let remaining else { return false }
        return remaining + TimeInterval(seconds) > 0
    }

    /// Adds or subtracts time from the current countdown, keeping it running or paused.
    func adjust(bySeconds seconds: Int) {
        guard canAdjust(bySeconds: seconds) else { return }
        let delta = TimeInterval(seconds)
        switch state {
        case .running(let end): schedule(end: end.addingTimeInterval(delta))
        case .paused(let remaining): setState(.paused(remaining: remaining + delta))
        case .idle, .finished: break
        }
    }

    private func schedule(end: Date) {
        timer?.invalidate()
        let timer = Timer(fire: end, interval: 0, repeats: false) { [weak self] _ in
            self?.setState(.finished)
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        setState(.running(end: end))
    }

    func pause() {
        guard case .running(let end) = state else { return }
        timer?.invalidate()
        timer = nil
        setState(.paused(remaining: max(0, end.timeIntervalSinceNow)))
    }

    func resume() {
        guard case .paused(let remaining) = state else { return }
        schedule(end: Date().addingTimeInterval(remaining))
    }

    /// "Pause Timer" or "Resume Timer", for the menu bar and right-click menus.
    var pauseTitle: String {
        if case .paused = state { "Resume Timer" } else { "Pause Timer" }
    }

    func togglePause() {
        if case .paused = state { resume() } else { pause() }
    }

    /// Cancels a running or paused timer (or all of Pomodoro mode), or closes the "time's up" message.
    func stop() {
        timer?.invalidate()
        timer = nil
        label = nil
        pomodoro = nil
        setState(.idle)
    }

    private func setState(_ newState: State) {
        state = newState
        onStateChange?()
    }

    /// "4:05" or "1:02:03".
    static func format(_ remaining: TimeInterval) -> String {
        let total = max(0, Int(remaining.rounded(.up)))
        let hours = total / 3600, minutes = (total % 3600) / 60, seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%d:%02d", minutes, seconds)
    }
}
