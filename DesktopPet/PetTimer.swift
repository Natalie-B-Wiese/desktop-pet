import Foundation
import Observation

/// A countdown that ends at a fixed date, so it stays accurate across sleep.
@Observable
final class PetTimer {
    enum State: Equatable {
        case idle
        case running(end: Date)
        case finished
    }

    private(set) var state: State = .idle

    @ObservationIgnored var onStateChange: (() -> Void)?
    @ObservationIgnored private var timer: Timer?

    static let presetMinutes = [1, 5, 10, 15, 25, 30, 45, 60]

    var isActive: Bool { state != .idle }

    func start(duration: TimeInterval) {
        let end = Date().addingTimeInterval(duration)
        timer?.invalidate()
        let timer = Timer(fire: end, interval: 0, repeats: false) { [weak self] _ in
            self?.setState(.finished)
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        setState(.running(end: end))
    }

    /// Cancels a running timer, or closes the "time's up" message.
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
