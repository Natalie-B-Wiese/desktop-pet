import AppKit
import EventKit

/// A meeting from the Mac's Calendar app, which syncs Google Calendar (added in System Settings → Internet Accounts).
struct Meeting {
    /// Stays the same when the meeting is moved, so pulling again updates its reminder instead of adding another.
    let id: String
    let start: Date
    let title: String
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
        let predicate = store.predicateForEvents(withStart: now, end: endOfDay, calendars: nil)

        return store.events(matching: predicate)
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
                    title: title.isEmpty ? "Meeting" : title
                )
            }
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
