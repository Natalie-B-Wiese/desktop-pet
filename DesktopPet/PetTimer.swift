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
    }

    private(set) var state: State = .idle

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

    func start(duration: TimeInterval) {
        schedule(end: Date().addingTimeInterval(duration))
    }

    /// Whether adding `minutes` (negative to subtract) would leave time on the clock.
    func canAdjust(byMinutes minutes: Int) -> Bool {
        guard let remaining else { return false }
        return remaining + TimeInterval(minutes * 60) > 0
    }

    /// Adds or subtracts time from the current countdown, keeping it running or paused.
    func adjust(byMinutes minutes: Int) {
        guard canAdjust(byMinutes: minutes) else { return }
        let delta = TimeInterval(minutes * 60)
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
        start(duration: remaining)
    }

    /// "Pause Timer" or "Resume Timer", for the menu bar and right-click menus.
    var pauseTitle: String {
        if case .paused = state { "Resume Timer" } else { "Pause Timer" }
    }

    func togglePause() {
        if case .paused = state { resume() } else { pause() }
    }

    /// Cancels a running or paused timer, or closes the "time's up" message.
    func stop() {
        timer?.invalidate()
        timer = nil
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
