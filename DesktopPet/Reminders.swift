import AppKit
import Observation

/// A one-time "remind me at 3:00 PM" reminder.
struct Reminder: Codable, Identifiable, Equatable {
    var id = UUID()
    var date: Date
    /// Optional text, like "Call mom". Nil means the cat just says "Reminder!".
    var message: String?
}

/// All reminders, saved across launches. A reminder stays in the list until it's closed,
/// so ones that came due while the app was closed or the Mac was asleep still show up.
@Observable
final class ReminderStore {
    /// Every reminder, soonest first.
    private(set) var reminders: [Reminder] = []

    /// Reminders whose time has come, oldest first. The bubble shows the first one.
    private(set) var due: [Reminder] = []

    /// Reminders that haven't come due yet.
    var upcoming: [Reminder] { reminders.filter { !due.contains($0) } }

    /// Called whenever reminders are added, deleted, or come due.
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?

    static let maxMessageLength = 40
    private static let storageKey = "reminders"

    init() {
        load()
        refresh()
        // Timers don't fire during sleep, so check again as soon as the Mac wakes.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.refresh() }
    }

    deinit {
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    }

    /// Adds a reminder at the next time the clock shows `time`'s hour and minute (today or tomorrow).
    func add(at time: Date, message: String?) {
        reminders.append(Reminder(date: Self.nextOccurrence(of: time), message: message))
        reminders.sort { $0.date < $1.date }
        save()
        refresh()
        onChange?()
    }

    /// Moves a reminder to the next time the clock shows `time`'s hour and minute, and changes its message.
    func update(_ id: Reminder.ID, at time: Date, message: String?) {
        guard let index = reminders.firstIndex(where: { $0.id == id }) else { return }
        reminders[index].date = Self.nextOccurrence(of: time)
        reminders[index].message = message
        reminders.sort { $0.date < $1.date }
        save()
        refresh()
        onChange?()
    }

    func delete(_ id: Reminder.ID) {
        reminders.removeAll { $0.id == id }
        save()
        refresh()
        onChange?()
    }

    /// Closes the reminder the bubble is showing.
    func dismissFirstDue() {
        if let first = due.first { delete(first.id) }
    }

    /// Recomputes which reminders are due and schedules a wake-up for the next one.
    private func refresh() {
        let now = Date()
        let newDue = reminders.filter { $0.date <= now }
        if newDue != due {
            due = newDue
            onChange?()
        }

        timer?.invalidate()
        timer = nil
        if let next = reminders.first(where: { $0.date > now }) {
            let timer = Timer(fire: next.date, interval: 0, repeats: false) { [weak self] _ in
                self?.refresh()
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let saved = try? JSONDecoder().decode([Reminder].self, from: data) else { return }
        reminders = saved.sorted { $0.date < $1.date }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(reminders) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    // MARK: - Helpers

    /// The next moment (after now) whose hour and minute match `time`.
    static func nextOccurrence(of time: Date, after now: Date = Date()) -> Date {
        let calendar = Calendar.current
        let parts = calendar.dateComponents([.hour, .minute], from: time)
        return calendar.nextDate(after: now, matching: parts, matchingPolicy: .nextTime) ?? time
    }

    /// "Today" or "Tomorrow", for showing when a time picked now would go off.
    static func dayWord(for time: Date) -> String {
        Calendar.current.isDateInToday(nextOccurrence(of: time)) ? "Today" : "Tomorrow"
    }

    /// "3:00 PM", or "Tomorrow 3:00 PM" / "Mon 3:00 PM" when it isn't today.
    static func timeText(_ date: Date) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return time }
        if calendar.isDateInTomorrow(date) { return "Tomorrow \(time)" }
        return "\(date.formatted(.dateTime.weekday(.abbreviated))) \(time)"
    }

    /// The top of the next hour, a sensible starting time for a new reminder.
    static func defaultTime(after now: Date = Date()) -> Date {
        let calendar = Calendar.current
        let hourStart = calendar.dateInterval(of: .hour, for: now)?.start ?? now
        return calendar.date(byAdding: .hour, value: 1, to: hourStart) ?? now
    }

    static func cleanMessage(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(maxMessageLength))
    }
}
