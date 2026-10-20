import Foundation
import Observation
import SwiftUI

/// How the pet talks, picked as Chatter in Settings; every chatter line comes in each one's voice.
enum Personality: String, CaseIterable {
    case bubbly, sassy

    var title: String {
        switch self {
        case .bubbly: "Bubbly"
        case .sassy: "Sassy"
        }
    }
}

/// When the pet says something. She only talks when something happens, so she never gets distracting.
enum ChatterMoment: Equatable {
    /// The greeting's top line, by the time of the first visit of the day.
    case morning, afternoon, evening
    /// The greeting's day line, by `Calendar` weekday (1 = Sunday).
    case weekday(Int)
    case lunch
    /// In the small bubble above the To-dos page.
    case todoChecked, allTodosDone
    /// In the small bubble beside the pet, when picking a personality in Settings.
    case preview
    /// In the side bubble (shortly after the hop), a few minutes before a reminder (Settings → Reminders), while the main bubble
    /// shows the reminder itself, so the lines never say when it is.
    case headsUp

    fileprivate var key: String {
        switch self {
        case .morning: "morning"
        case .afternoon: "afternoon"
        case .evening: "evening"
        case .weekday(let day): "weekday\(day)"
        case .lunch: "lunch"
        case .todoChecked: "todoChecked"
        case .allTodosDone: "allTodosDone"
        case .preview: "preview"
        case .headsUp: "headsUp"
        }
    }
}

enum Chatter {
    /// A line for `moment`. Lines are dealt from a shuffled deck (saved across launches),
    /// so none repeats until all of that moment's lines have shown.
    static func line(_ moment: ChatterMoment, _ personality: Personality) -> String {
        let all = lines(moment, personality)
        let key = "chatter.deck.\(personality.rawValue).\(moment.key)"
        let defaults = UserDefaults.standard
        // Lines removed since the deck was saved are dropped.
        var deck = (defaults.stringArray(forKey: key) ?? []).filter(all.contains)
        if deck.isEmpty {
            deck = all.shuffled()
            // A fresh deck never starts with the line just said.
            if deck.count > 1, deck.first == defaults.string(forKey: key + ".last") { deck.swapAt(0, 1) }
        }
        let line = deck.removeFirst()
        defaults.set(deck, forKey: key)
        defaults.set(line, forKey: key + ".last")
        return line
    }

    /// Whole minutes left until `date`, rounded up, at least 1.
    static func minutesLeft(until date: Date, from now: Date = Date()) -> Int {
        max(1, Int((date.timeIntervalSince(now) / 60).rounded(.up)))
    }

    /// "5 min", "1 hr", "1 hr 30 min", with non-breaking spaces so "min" never wraps away from its number.
    static func durationText(minutes: Int) -> String {
        let hours = minutes / 60, rest = minutes % 60
        if hours == 0 { return "\(minutes)\u{A0}min" }
        return rest == 0 ? "\(hours)\u{A0}hr" : "\(hours)\u{A0}hr\u{A0}\(rest)\u{A0}min"
    }

    static func lines(_ moment: ChatterMoment, _ personality: Personality) -> [String] {
        switch personality {
        case .bubbly: bubbly(moment)
        case .sassy: sassy(moment)
        }
    }

    private static func bubbly(_ moment: ChatterMoment) -> [String] {
        switch moment {
        case .morning: ["Morning! Power-up first? (Coffee.)", "Coffee first, then greatness."]
        case .afternoon: ["Afternoons go hard."]
        case .evening: ["Evening! Let's keep it chill."]
        case .weekday(let day):
            switch day {
            case 1: ["Sunday. Snacks and vibes only."]
            case 2: ["Fresh week. We're so back."]
            case 3: ["Tuesday. Lowkey a great day."]
            case 4: ["Wednesday. Halfway there."]
            case 5: ["Thursday. Basically Friday's warm-up."]
            case 6: ["It's Friday. We made it."]
            default: ["Weekend mode: on."]
            }
        case .lunch: ["Lunch break? Asking for a friend.", "Food buff time."]
        case .todoChecked: [
            "That one never stood a chance.",
            "Task complete! Efficiency +1",
            "It's giving productive.",
            "That's one less thing living rent-free in your head.",
            "Main character energy, honestly. Respect.",
        ]
        case .allTodosDone: ["Cleared the whole list? Iconic.", "You're the GOAT."]
        case .preview: ["Vibe check: PASSED!"]
        case .headsUp: [
            "Don't lock-in too hard. Reminder incoming!",
            "Something's coming up. We're so ready.",
            "Heads up!",
        ]
        }
    }

    private static func sassy(_ moment: ChatterMoment) -> [String] {
        switch moment {
        case .morning: ["Good morning. Yes, I woke up flawless.", "The star of your desktop has arrived."]
        case .afternoon: [
            "Good afternoon. I've been fabulous all day without you.",
            "I've been fabulous for hours. It's tiring.",
            "This afternoon could use more me.",
        ]
        case .evening: ["Good evening. Fashionably late, I see."]
        case .weekday(let day):
            switch day {
            case 1: ["Sunday. A day of rest. I'm a natural."]
            case 2: ["Monday. How dare it."]
            case 3: ["Tuesday. Monday's less famous sequel."]
            case 4: ["Wednesday. Halfway to my weekend."]
            case 5: ["Thursday. Friday's opening act."]
            case 6: ["Friday. Finally, an event worthy of me."]
            default: ["Saturday. I deserve it. You too, I suppose."]
            }
        case .lunch: ["Feed yourself. I need my human at full strength.", "Lunch. Something worthy of us, please."]
        case .todoChecked: [
            "Clearly my influence.",
            "Stunning work. I'd know.",
            "I'll accept your thanks now.",
            "Impressive. Almost as impressive as me.",
            "Handled. Under my supervision.",
        ]
        case .allTodosDone: ["Flawless. I'd expect nothing less from my human.", "A clean list. We make a stunning team."]
        case .preview: ["Bow down. Kidding. Mostly."]
        case .headsUp: [
            "A little warning, because I'm generous.",
            "Plans? Without me?",
            "Something's coming up. I'll allow it.",
        ]
        }
    }
}

/// What the pet is saying right now: a line in the bubble while the menu is closed, or a small
/// second bubble above an open page (to-dos, Settings). Both go away on their own.
@Observable
final class ChatterStore {
    /// Shown in the bubble when nothing else is (no menu, reminder, greeting or timer). Clicking closes it.
    var line: String? {
        didSet { if line != oldValue { onChange?() } }
    }

    /// The small bubble beside the pet.
    private(set) var pageLine: String? {
        didSet { if pageLine != oldValue { onChange?() } }
    }

    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private var lineID = 0
    @ObservationIgnored private var pageLineID = 0

    static let lineDuration: TimeInterval = 7
    static let pageLineDuration: TimeInterval = 4

    func say(_ text: String) {
        lineID += 1
        let id = lineID
        line = text
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.lineDuration) { [weak self] in
            if self?.lineID == id { self?.line = nil }
        }
    }

    func sayAbovePage(_ text: String) {
        pageLineID += 1
        let id = pageLineID
        pageLine = text
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.pageLineDuration) { [weak self] in
            guard let self, pageLineID == id else { return }
            pageLine = nil
        }
    }

    func clearPageLine() {
        pageLineID += 1
        pageLine = nil
    }
}

/// A heads-up in the main bubble, laid out like a due reminder: "🔔 In 5 min · 8:20 PM" over the message.
/// Clicking the bubble closes it. Her personality's line goes in the side bubble.
struct BubbleHeadsUp: View {
    let reminder: Reminder
    /// How many more are waiting after this one, like the due reminder's "· N more".
    let moreCount: Int

    var body: some View {
        VStack(spacing: 1) {
            // Counts down while it waits to be clicked.
            TimelineView(.periodic(from: .now, by: 5)) { context in
                HStack(spacing: 4) {
                    // Meetings get the meeting rows' calendar mark, your own reminders the bell.
                    Image(systemName: reminder.meetingID == nil ? "bell.fill" : "calendar")
                        .font(.system(size: 9, weight: .bold))
                    Text("In \(Chatter.durationText(minutes: Chatter.minutesLeft(until: reminder.date, from: context.date))) · \(AppPreferences.clockText(reminder.shownDate))")
                        .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                }
            }
            WrappingWidth(maxWidth: 180) {
                Text(reminder.message ?? "Reminder")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
            }
            Text(moreCount > 0 ? "Click to close · \(moreCount) more" : "Click to close")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .opacity(0.55)
        }
    }
}

/// The line in the bubble while the menu is closed.
struct BubbleChatterLine: View {
    let text: String

    var body: some View {
        WrappingWidth(maxWidth: 180) {
            Text(text)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
        }
    }
}

/// The small bubble beside the pet (in its own window), with its tail pointing at her.
struct BubblePageLine: View {
    let text: String
    /// Her on the left, so the tail points left; false when the bubble sits on her left.
    let tailOnLeft: Bool

    private static let tailWidth: CGFloat = 6

    var body: some View {
        WrappingWidth(maxWidth: 170) {
            Text(text)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.black)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .padding(tailOnLeft ? .leading : .trailing, Self.tailWidth)
        .background {
            let shape = SideBubbleShape(tailWidth: Self.tailWidth, tailOnLeft: tailOnLeft)
            shape.fill(.white)
            shape.stroke(.black, lineWidth: 2)
        }
        .padding(2) // room for the outline
        .fixedSize()
        .environment(\.colorScheme, .light)
    }
}

/// A rounded bubble with its tail halfway down its left or right side.
private struct SideBubbleShape: Shape {
    var tailWidth: CGFloat
    var tailOnLeft: Bool

    func path(in rect: CGRect) -> Path {
        let radius: CGFloat = 10
        let tailHalfHeight: CGFloat = 6
        let body = tailOnLeft
            ? CGRect(x: rect.minX + tailWidth, y: rect.minY, width: rect.width - tailWidth, height: rect.height)
            : CGRect(x: rect.minX, y: rect.minY, width: rect.width - tailWidth, height: rect.height)
        let y = rect.midY
        var tail = Path()
        if tailOnLeft {
            tail.move(to: CGPoint(x: body.minX + 1, y: y - tailHalfHeight))
            tail.addLine(to: CGPoint(x: rect.minX, y: y))
            tail.addLine(to: CGPoint(x: body.minX + 1, y: y + tailHalfHeight))
        } else {
            tail.move(to: CGPoint(x: body.maxX - 1, y: y - tailHalfHeight))
            tail.addLine(to: CGPoint(x: rect.maxX, y: y))
            tail.addLine(to: CGPoint(x: body.maxX - 1, y: y + tailHalfHeight))
        }
        tail.closeSubpath()
        return Path(roundedRect: body, cornerRadius: min(radius, body.height / 2)).union(tail)
    }
}
