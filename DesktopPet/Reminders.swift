import AppKit
import Observation

/// A "remind me at 3:00 PM" reminder, once or on certain days of the week.
struct Reminder: Codable, Identifiable, Equatable {
    var id = UUID()
    var date: Date
    /// Optional text, like "Call mom". Nil means the cat just says "Reminder!".
    var message: String?
    /// The weekdays it repeats on (1 = Sunday … 7 = Saturday, like `Calendar`). Nil or empty means it goes off once.
    /// When a repeating reminder is closed, it moves to its next day instead of being deleted.
    var repeatDays: Set<Int>?
    /// Set when it was pulled from a calendar meeting, so pulling again updates it instead of adding another.
    /// These can't be edited (the calendar decides their time and title), only deleted.
    var meetingID: String?
    /// When the meeting starts, which is also when its reminder comes due.
    var meetingStart: Date?
    /// The meeting's Zoom (or Meet, Teams) link, shown as a Join button. Pulled from the calendar,
    /// or typed in for her own reminders.
    var meetingLink: URL?

    /// When a snoozed reminder comes back. Kept apart from `date`, so snoozing never changes its own time
    /// (a daily 2:00 PM reminder snoozed once stays a 2:00 PM one, and a meeting's stays at its start).
    /// Cleared when it's closed or its time changes.
    var snoozedUntil: Date?
    /// All the snoozes added up ("snoozed 15 min" on the due reminder), so you can tell you've put it off before.
    /// Cleared with `snoozedUntil`. Optional, so reminders saved before it still load.
    var snoozedMinutes: Int?

    /// The time to show for it: the meeting's start for a meeting, otherwise when it goes off.
    var shownDate: Date { meetingStart ?? date }

    /// When it comes due: the snooze time if it's snoozed, otherwise its time.
    var dueDate: Date { snoozedUntil ?? date }

    /// Tells one occurrence of a repeating reminder from the next, so each gets its own heads-up.
    var occurrenceKey: String { "\(id)|\(Int(date.timeIntervalSince1970))" }

    var repeats: Bool { !(repeatDays ?? []).isEmpty }
}

/// All reminders, saved across launches. A reminder stays in the list until it's closed,
/// so ones that came due while the app was closed or the Mac was asleep still show up.
@Observable
final class ReminderStore {
    /// Every reminder, soonest due first.
    private(set) var reminders: [Reminder] = []

    /// Reminders whose time has come, oldest first. The bubble shows the first one.
    private(set) var due: [Reminder] = []

    /// Reminders coming up within the heads-up time (Settings → Reminders), soonest first, not yet clicked away.
    /// The bubble shows the first one after any due reminders.
    private(set) var headsUp: [Reminder] = []

    /// Reminders that haven't come due yet.
    var upcoming: [Reminder] { reminders.filter { !due.contains($0) } }

    /// Heads-ups already closed, or skipped because the reminder was set inside the heads-up time.
    @ObservationIgnored private var headsUpDone: Set<String> = []

    /// Called whenever reminders are added, deleted, or come due.
    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?

    static let maxMessageLength = 40
    private static let storageKey = "reminders"
    /// When meetings were last pulled (by the button or the daily pull), so the daily pull runs once a day.
    private static let lastMeetingPullKey = "reminders.lastMeetingPull"

    var pulledMeetingsToday: Bool {
        guard let last = UserDefaults.standard.object(forKey: Self.lastMeetingPullKey) as? Date else { return false }
        return Calendar.current.isDateInToday(last)
    }

    init() {
        load()
        // Meeting reminders used to go off early; now they come due at the start, and the heads-up warns ahead.
        for index in reminders.indices {
            if let start = reminders[index].meetingStart { reminders[index].date = start }
        }
        refresh()
        // Timers don't fire during sleep, so check again as soon as the Mac wakes.
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.refresh() }
    }

    deinit {
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    }

    /// Adds a reminder at the next time the clock shows `time`'s hour and minute (on one of `repeatDays`, if any).
    func add(at time: Date, repeatDays: Set<Int>, message: String?, link: URL? = nil) {
        let days = repeatDays.isEmpty ? nil : repeatDays
        let reminder = Reminder(date: Self.nextOccurrence(of: time, on: days), message: message, repeatDays: days, meetingLink: link)
        reminders.append(reminder)
        skipHeadsUpIfSoon(reminder)
        reminders.sort { $0.dueDate < $1.dueDate }
        save()
        refresh()
        onChange?()
    }

    /// For testing: a one-time reminder at exactly `date` (seconds included, unlike `add`), with no heads-up.
    func addForTesting(at date: Date, message: String?) {
        let reminder = Reminder(date: date, message: message, repeatDays: nil)
        reminders.append(reminder)
        headsUpDone.insert(reminder.occurrenceKey)
        reminders.sort { $0.dueDate < $1.dueDate }
        save()
        refresh()
        onChange?()
    }

    /// Moves a reminder to the next time the clock shows `time`'s hour and minute, and changes its days, message and link.
    func update(_ id: Reminder.ID, at time: Date, repeatDays: Set<Int>, message: String?, link: URL?) {
        guard let index = reminders.firstIndex(where: { $0.id == id }) else { return }
        let days = repeatDays.isEmpty ? nil : repeatDays
        reminders[index].date = Self.nextOccurrence(of: time, on: days)
        reminders[index].repeatDays = days
        reminders[index].message = message
        reminders[index].meetingLink = link
        reminders[index].snoozedUntil = nil
        reminders[index].snoozedMinutes = nil
        skipHeadsUpIfSoon(reminders[index])
        reminders.sort { $0.dueDate < $1.dueDate }
        save()
        refresh()
        onChange?()
    }

    /// Adds a reminder for each meeting, updates ones whose meeting moved or was renamed, and removes ones
    /// for today's meetings that are gone (canceled, declined or moved to another day).
    @discardableResult
    func syncMeetings(_ meetings: [Meeting]) -> (added: Int, changed: Int) {
        var added = 0, changed = 0
        for meeting in meetings {
            let message = Self.cleanMessage(meeting.title)
            if let index = reminders.firstIndex(where: { $0.meetingID == meeting.id }) {
                guard reminders[index].meetingStart != meeting.start || reminders[index].message != message
                        || reminders[index].meetingLink != meeting.link else { continue }
                // A meeting that moved makes its snooze meaningless; a rename keeps it.
                if reminders[index].meetingStart != meeting.start {
                    reminders[index].snoozedUntil = nil
                    reminders[index].snoozedMinutes = nil
                }
                reminders[index].date = meeting.start
                reminders[index].meetingStart = meeting.start
                reminders[index].message = message
                reminders[index].meetingLink = meeting.link
                skipHeadsUpIfSoon(reminders[index])
                changed += 1
            } else {
                let reminder = Reminder(date: meeting.start, message: message, meetingID: meeting.id, meetingStart: meeting.start, meetingLink: meeting.link)
                reminders.append(reminder)
                skipHeadsUpIfSoon(reminder)
                added += 1
            }
        }

        let now = Date()
        let pulledIDs = Set(meetings.map(\.id))
        let before = reminders.count
        reminders.removeAll { reminder in
            guard let id = reminder.meetingID, let start = reminder.meetingStart else { return false }
            return start > now && Calendar.current.isDateInToday(start) && !pulledIDs.contains(id)
        }
        changed += before - reminders.count

        reminders.sort { $0.dueDate < $1.dueDate }
        save()
        UserDefaults.standard.set(Date(), forKey: Self.lastMeetingPullKey)
        refresh()
        onChange?()
        return (added, changed)
    }

    /// Rechecks heads-ups after the Settings → Reminders time changes.
    func applyHeadsUpChange() {
        refresh()
    }

    /// Closes the heads-up the bubble is showing. The reminder still comes due at its time.
    func dismissFirstHeadsUp() {
        guard let first = headsUp.first else { return }
        headsUpDone.insert(first.occurrenceKey)
        refresh()
    }

    /// A reminder set (or moved) to inside the heads-up time skips its heads-up and just comes due.
    private func skipHeadsUpIfSoon(_ reminder: Reminder) {
        if reminder.date.timeIntervalSinceNow < Self.headsUpLead { headsUpDone.insert(reminder.occurrenceKey) }
    }

    private static var headsUpLead: TimeInterval { 60 * Double(AppPreferences.headsUpMinutes) }

    func delete(_ id: Reminder.ID) {
        reminders.removeAll { $0.id == id }
        save()
        refresh()
        onChange?()
    }

    /// Closes the reminder the bubble is showing. A repeating one moves to its next day after now,
    /// so days missed while the Mac was off don't pile up.
    func dismissFirstDue() {
        guard let first = due.first else { return }
        guard first.repeats, let index = reminders.firstIndex(where: { $0.id == first.id }) else {
            delete(first.id)
            return
        }
        reminders[index].date = Self.nextOccurrence(of: first.date, on: first.repeatDays)
        reminders[index].snoozedUntil = nil
        reminders[index].snoozedMinutes = nil
        reminders.sort { $0.dueDate < $1.dueDate }
        save()
        refresh()
        onChange?()
    }

    /// Puts the reminder the bubble is showing off for `minutes`. A repeating one keeps its time for the next days.
    /// It gets no heads-up before it comes back.
    func snoozeFirstDue(minutes: Int) {
        guard let first = due.first, let index = reminders.firstIndex(where: { $0.id == first.id }) else { return }
        reminders[index].snoozedUntil = Date().addingTimeInterval(60 * Double(minutes))
        reminders[index].snoozedMinutes = (reminders[index].snoozedMinutes ?? 0) + minutes
        reminders.sort { $0.dueDate < $1.dueDate }
        save()
        refresh()
        onChange?()
    }

    /// Recomputes which reminders are due and schedules a wake-up for the next one.
    private func refresh() {
        let now = Date()
        let newDue = reminders.filter { $0.dueDate <= now }
        let lead = Self.headsUpLead
        // A snoozed reminder skips the heads-up; it just comes back.
        let newHeadsUp = lead <= 0 ? [] : reminders.filter {
            $0.snoozedUntil == nil && $0.date > now && $0.date.timeIntervalSince(now) <= lead && !headsUpDone.contains($0.occurrenceKey)
        }
        if newDue != due || newHeadsUp != headsUp {
            due = newDue
            headsUp = newHeadsUp
            onChange?()
        }

        timer?.invalidate()
        timer = nil
        // The next moment something changes: a reminder comes due (or back from a snooze) or its heads-up starts.
        let next = reminders.flatMap { reminder in
            reminder.snoozedUntil.map { [$0] } ?? [reminder.date, reminder.date.addingTimeInterval(-lead)]
        }.filter { $0 > now }.min()
        if let next {
            let timer = Timer(fire: next, interval: 0, repeats: false) { [weak self] _ in
                self?.refresh()
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let saved = try? JSONDecoder().decode([Reminder].self, from: data) else { return }
        reminders = saved.sorted { $0.dueDate < $1.dueDate }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(reminders) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    // MARK: - Helpers

    /// The next moment (after now) whose hour and minute match `time`, on one of `days` (weekday numbers) if given.
    static func nextOccurrence(of time: Date, on days: Set<Int>? = nil, after now: Date = Date()) -> Date {
        let calendar = Calendar.current
        let parts = calendar.dateComponents([.hour, .minute], from: time)
        guard let days, !days.isEmpty else {
            return calendar.nextDate(after: now, matching: parts, matchingPolicy: .nextTime) ?? time
        }
        return days.compactMap { weekday in
            var dayParts = parts
            dayParts.weekday = weekday
            return calendar.nextDate(after: now, matching: dayParts, matchingPolicy: .nextTime)
        }.min() ?? time
    }

    /// When a time picked now would go off: "Today" or "Tomorrow", or the repeat days ("Every day", "Weekdays", "Mon, Wed").
    static func dayWord(for time: Date, repeatDays: Set<Int> = []) -> String {
        if !repeatDays.isEmpty { return repeatText(repeatDays) }
        return Calendar.current.isDateInToday(nextOccurrence(of: time)) ? "Today" : "Tomorrow"
    }

    /// Roughly when in the day an hour (0…23) is, so 12 PM reads as "Noon" and 12 AM as "Midnight".
    static func partOfDay(hour24: Int) -> String {
        switch hour24 {
        case 0: "Midnight"
        case 1..<5: "Early morning"
        case 5..<12: "Morning"
        case 12: "Noon"
        case 13..<17: "Afternoon"
        case 17..<21: "Evening"
        default: "Night"
        }
    }

    /// The weekdays in the order this Mac's calendar starts its week (Sunday first in the US).
    static var orderedWeekdays: [Int] {
        let first = Calendar.current.firstWeekday
        return (0..<7).map { (first - 1 + $0) % 7 + 1 }
    }

    /// "Every day", "Weekdays", "Weekends", or the days in week order, like "Mon, Wed, Fri".
    static func repeatText(_ days: Set<Int>) -> String {
        switch days {
        case Set(1...7): return "Every day"
        case Set(2...6): return "Weekdays"
        case [1, 7]: return "Weekends"
        default:
            let names = Calendar.current.shortWeekdaySymbols
            let list = orderedWeekdays.filter(days.contains).map { names[$0 - 1] }
            return list.count == 1 ? "Every \(list[0])" : list.joined(separator: ", ")
        }
    }

    /// "3:00 PM", or "Tomorrow 3:00 PM" / "Mon 3:00 PM" when it isn't today (24-hour with military time on).
    static func timeText(_ date: Date) -> String {
        let time = AppPreferences.clockText(date)
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
