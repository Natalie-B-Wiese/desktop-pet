import Foundation
import Observation
import SwiftUI

/// What Topsy says the first time you're at the Mac each day.
struct MorningGreeting: Equatable {
    /// When it was made, for the date in the title.
    let date: Date
    /// The rest of today's meetings, soonest first, or nil without Calendar access (then there's no meetings line).
    let meetings: [Meeting]?
    /// Today's all-day events: birthdays, holidays, "Out of office".
    let allDayEvents: [String]

    /// No greeting before this hour, so the midnight day change doesn't greet a night owl.
    static let earliestHour = 4

    /// The title, just the facts: "Wednesday, Oct 21". (Natalie chose this over "Good morning!" and a weekday
    /// line; saying hi is left to her personality.)
    var title: String {
        date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }
}

extension Meeting: Equatable {
    static func == (a: Meeting, b: Meeting) -> Bool { a.id == b.id && a.start == b.start && a.title == b.title }
}

/// Holds the greeting while it's in the bubble, and remembers the day it was last shown so it comes once a day.
@Observable
final class GreetingStore {
    private(set) var current: MorningGreeting?

    /// Called when a greeting appears or is closed.
    @ObservationIgnored var onChange: (() -> Void)?

    private static let lastShownKey = "greeting.lastShown"

    var shownToday: Bool {
        guard let last = UserDefaults.standard.object(forKey: Self.lastShownKey) as? Date else { return false }
        return Calendar.current.isDateInToday(last)
    }

    /// `remember: false` is for testing, so it doesn't use up today's real greeting.
    func show(_ greeting: MorningGreeting, remember: Bool = true) {
        if remember { UserDefaults.standard.set(greeting.date, forKey: Self.lastShownKey) }
        current = greeting
        onChange?()
    }

    func dismiss() {
        current = nil
        onChange?()
    }
}

/// The greeting in the bubble. Clicking the bubble closes it.
struct BubbleGreeting: View {
    let greeting: MorningGreeting
    /// Live, so checking one off while the greeting is up changes the count.
    let todosLeft: Int
    /// How many more are waiting behind it, like a finished timer.
    let moreCount: Int

    private static let maxAllDayShown = 3

    var body: some View {
        VStack(spacing: 6) {
            Text(greeting.title)
                .font(.system(size: 16, weight: .bold, design: .rounded))

            VStack(alignment: .leading, spacing: 4) {
                row("checklist", todosLeft == 0 ? "No to-dos left" : todosLeft == 1 ? "1 to-do left" : "\(todosLeft) to-dos left")
                if let meetings = greeting.meetings {
                    if let first = meetings.first {
                        let time = AppPreferences.clockText(first.start)
                        row("calendar", meetings.count == 1 ? "1 meeting at \(time)" : "\(meetings.count) meetings, first at \(time)",
                            detail: first.title)
                    } else {
                        row("calendar", "No meetings today")
                    }
                }
                ForEach(greeting.allDayEvents.prefix(Self.maxAllDayShown), id: \.self) { title in
                    row("star", title)
                }
                if greeting.allDayEvents.count > Self.maxAllDayShown {
                    row("star", "\(greeting.allDayEvents.count - Self.maxAllDayShown) more today")
                }
            }
            .frame(maxWidth: 180, alignment: .leading)

            Text(moreCount > 0 ? "Click to close · \(moreCount) more" : "Click to close")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .opacity(0.55)
        }
    }

    private func row(_ systemImage: String, _ text: String, detail: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 10, weight: .bold))
                .opacity(0.55)
                .frame(width: 13)
            VStack(alignment: .leading, spacing: 0) {
                Text(text)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                if let detail {
                    Text(detail)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .opacity(0.55)
                }
            }
            .lineLimit(1)
            .truncationMode(.tail)
        }
    }
}
