import AppKit
import EventKit

/// A meeting from the Mac's Calendar app, which syncs Google Calendar (added in System Settings → Internet Accounts).
struct Meeting {
    /// Stays the same when the meeting is moved, so pulling again updates its reminder instead of adding another.
    let id: String
    let start: Date
    let title: String
    /// Its Zoom, Meet or Teams link, if the invitation has one.
    let link: URL?
}

/// One of the Mac's calendars, for choosing which ones Topsy reads.
struct MeetingCalendar: Identifiable {
    let id: String
    let title: String
    /// The account it belongs to, like "Google" or "iCloud".
    let account: String
    let color: NSColor

    /// Calendar IDs can change when an account syncs from scratch, so a hidden one is also matched by its account and title.
    var name: String { "\(account)|\(title)" }
}

/// Reads today's meetings with EventKit. Going through the Calendar app means no Google sign-in of our own.
enum CalendarMeetings {
    enum PullError: Error { case noAccess }

    private static let store = EKEventStore()

    /// The rest of today's meetings, soonest first: not started yet, not all-day, not canceled or declined.
    static func todaysUpcoming() async throws -> [Meeting] {
        guard try await requestAccess() else { throw PullError.noAccess }

        let now = Date()
        let calendar = Calendar.current
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        return events(from: now, to: endOfDay)
            .filter { event in
                !event.isAllDay && event.status != .canceled && event.startDate > now && !declined(event)
            }
            .sorted { $0.startDate < $1.startDate }
            .map { event in
                // A repeating meeting shares one eventIdentifier, so the occurrence's original date tells them apart.
                let occurrence = (event.occurrenceDate ?? event.startDate).timeIntervalSince1970
                let title = event.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                return Meeting(
                    id: "\(event.eventIdentifier ?? event.calendarItemIdentifier)|\(Int(occurrence))",
                    start: event.startDate,
                    title: title.isEmpty ? "Meeting" : title,
                    link: MeetingLink.find(in: [event.url?.absoluteString, event.location, event.notes])
                )
            }
    }

    /// Titles of today's all-day events (birthdays, holidays, "Out of office") for the morning greeting,
    /// skipping canceled and declined ones and repeats across calendars. Empty without Calendar access.
    static func todaysAllDayEvents() -> [String] {
        guard hasAccess else { return [] }
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
        var titles: [String] = []
        for event in events(from: startOfDay, to: endOfDay)
        where event.isAllDay && event.status != .canceled && !declined(event) {
            let title = event.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !title.isEmpty && !titles.contains(title) { titles.append(title) }
        }
        return titles
    }

    /// Whether a meeting is going on right now (not all-day, canceled or declined), so chatter keeps quiet,
    /// e.g. while you share your screen. False without Calendar access.
    static func isInMeeting() -> Bool {
        guard hasAccess else { return false }
        let now = Date()
        return events(from: now.addingTimeInterval(-24 * 3600), to: now.addingTimeInterval(1)).contains { event in
            !event.isAllDay && event.status != .canceled && !declined(event)
                && event.startDate <= now && event.endDate > now
        }
    }

    // MARK: - Choosing calendars

    /// Hidden rather than shown, so a calendar added later is read until you hide it.
    private static let hiddenKey = "reminders.hiddenCalendars"

    private struct HiddenCalendar: Codable, Equatable {
        let id: String
        let name: String
    }

    private static var hidden: [HiddenCalendar] {
        get {
            guard let data = UserDefaults.standard.data(forKey: hiddenKey),
                  let saved = try? JSONDecoder().decode([HiddenCalendar].self, from: data) else { return [] }
            return saved
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) { UserDefaults.standard.set(data, forKey: hiddenKey) }
        }
    }

    /// Every calendar that holds events, grouped by account, asking for access the first time.
    static func calendars() async throws -> [MeetingCalendar] {
        guard try await requestAccess() else { throw PullError.noAccess }
        return store.calendars(for: .event)
            .map(meetingCalendar)
            .sorted {
                $0.account == $1.account
                    ? $0.title.localizedStandardCompare($1.title) == .orderedAscending
                    : $0.account.localizedStandardCompare($1.account) == .orderedAscending
            }
    }

    static func isHidden(_ calendar: MeetingCalendar) -> Bool {
        hidden.contains { $0.id == calendar.id || $0.name == calendar.name }
    }

    static func setHidden(_ calendar: MeetingCalendar, _ isHidden: Bool) {
        var list = hidden.filter { $0.id != calendar.id && $0.name != calendar.name }
        if isHidden { list.append(HiddenCalendar(id: calendar.id, name: calendar.name)) }
        hidden = list
    }

    private static func meetingCalendar(_ calendar: EKCalendar) -> MeetingCalendar {
        MeetingCalendar(id: calendar.calendarIdentifier, title: calendar.title, account: calendar.source?.title ?? "", color: calendar.color)
    }

    /// Events from the calendars you haven't hidden.
    private static func events(from start: Date, to end: Date) -> [EKEvent] {
        let shown = store.calendars(for: .event).filter { !isHidden(meetingCalendar($0)) }
        // An empty list would mean every calendar to EventKit.
        guard !shown.isEmpty else { return [] }
        return store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: shown))
    }

    /// True once Calendar access was allowed. The daily pull checks this so it never pops up the permission dialog itself.
    static var hasAccess: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }

    /// Opens System Settings at Privacy → Calendars, to turn access back on after saying no.
    static func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Asks the first time; after that macOS remembers the answer.
    private static func requestAccess() async throws -> Bool {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            return true
        case .notDetermined:
            guard try await store.requestFullAccessToEvents() else { return false }
            store.reset() // events fetched before access was granted come back empty otherwise
            return true
        default:
            return false
        }
    }

    private static func declined(_ event: EKEvent) -> Bool {
        event.attendees?.contains { $0.isCurrentUser && $0.participantStatus == .declined } ?? false
    }
}
