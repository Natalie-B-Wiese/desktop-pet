import Foundation
import Observation
import SwiftUI

/// How the pet talks, picked as Chatter in Settings; every chatter line comes in each one's voice.
enum Personality: String, CaseIterable {
    case bubbly, sassy, boss, dark

    var title: String {
        switch self {
        case .bubbly: "Bubbly"
        case .sassy: "Sassy"
        case .boss: "Boss"
        case .dark: "Dark"
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
        case .boss: boss(moment)
        case .dark: dark(moment)
        }
    }

    /// Golden-retriever energy (for cats and dogs alike: no fetch, barking or sunbeams), a little Gen-Z, loves food and coffee.
    private static func bubbly(_ moment: ChatterMoment) -> [String] {
        switch moment {
        case .morning: ["Morning! Power-up first? (Coffee.)", "Morning! You're here! Best part of my day."]
        case .afternoon: ["Afternoons go hard.", "Afternoon! Snack break? SNACK BREAK?"]
        case .evening: ["Evening! Let's keep it chill.", "Evening zoomies, anyone?"]
        case .weekday(let day):
            switch day {
            case 1: ["Sunday. Snacks and vibes only."]
            case 2: ["Fresh week. We're SO back!"]
            case 3: ["Tuesday. Lowkey a great day."]
            case 4: ["Wednesday. Halfway there."]
            case 5: ["Thursday. Basically Friday's warm-up."]
            case 6: ["It's FRIDAY! We made it!"]
            default: ["Weekend mode: on."]
            }
        case .lunch: ["LUNCH?! Did someone say LUNCH?!", "Food buff time.", "Lunch break? Asking for a friend."]
        case .todoChecked: [
            "Checkbox go BOOP!",
            "Much productive. Very wow.",
            "That one never stood a chance.",
            "Task complete! Efficiency +1",
            "Main character energy, honestly. Respect.",
        ]
        case .allTodosDone: ["Zoomies unlocked!", "The WHOLE list?! You're the GOAT."]
        // Non-breaking spaces keep "Best. Day. EVER." on one line.
        case .preview: ["Hiii! You picked me! Best.\u{A0}Day.\u{A0}EVER."]
        case .headsUp: [
            "Zoomies incoming! Maybe the Zoom kind.",
            "Don't lock-in too hard. Reminder incoming!",
            "Boop! Reminder for you!",
        ]
        }
    }

    private static func sassy(_ moment: ChatterMoment) -> [String] {
        switch moment {
        case .morning: ["Good morning. Yes, I woke up flawless.", "Good morning. The day may now begin."]
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
        case .preview: ["The star of your desktop has arrived."]
        case .headsUp: [
            "A little warning, because I'm generous.",
            "Plans? Without me?",
            "Something's coming up. I'll allow it.",
        ]
        }
    }

    /// Topsy as the CEO of a tiny company where you're the star employee. Management approves of everything you do;
    /// never a real boss (no deadlines, "back to work" or working late).
    private static func boss(_ moment: ChatterMoment) -> [String] {
        switch moment {
        case .morning: ["Good morning, team. Today's agenda: greatness.", "Morning! Coffee is a business expense."]
        case .afternoon: ["Good afternoon. Let's circle back to excellence.", "Afternoon. Profits are up. I checked."]
        case .evening: ["Good evening. Your dedication has been noted."]
        case .weekday(let day):
            switch day {
            case 1: ["Sunday. The office is closed. Even I'm off."]
            case 2: ["Monday. New week, new goals."]
            case 3: ["Tuesday. Momentum is building."]
            case 4: ["Wednesday. Midweek report: we're crushing it."]
            case 5: ["Thursday. Friday is on the roadmap."]
            case 6: ["Friday. Let's close out the week strong."]
            default: ["Saturday. Company-wide day off. I signed it."]
            }
        case .lunch: ["The company has approved your lunch break!", "Lunch is now a mandatory meeting."]
        case .todoChecked: [
            "Now that's synergy.",
            "Impact player!",
            "Huge win for the team.",
            "That boosts morale!",
            "Great work! I'll tell the shareholders!",
        ]
        case .allTodosDone: ["Record quarter! Bonuses for everyone. (Treats.)", "Every item delivered. The board is speechless."]
        case .preview: ["Welcome aboard! Glad to have you on the team."]
        case .headsUp: [
            "Per my last email: something's coming up.",
            "Quick sync incoming.",
            "Calendar update from management.",
        ]
        }
    }

    /// A chill, cozy old soul who loves reading and tea, deadpan and a little off the wall, with a running bit about "they".
    /// Playfully mysterious but warm, never wary of you; no detective or fortune-teller lines.
    private static func dark(_ moment: ChatterMoment) -> [String] {
        switch moment {
        case .morning: ["Morning. Coffee first. Talking later.", "Good morning. I've been reading. Don't ask what."]
        case .afternoon: [
            "Good afternoon. Halfway through the day. And my book.",
            "Afternoon. The shadows are getting longer. Coincidence?",
        ]
        case .evening: [
            "Evening. My favorite time to think.",
            "Good evening. The best books are read at night.",
            "Long day? Tea and a book to relax?",
        ]
        case .weekday(let day):
            switch day {
            case 1: ["Sunday. Blankets and books. You're invited."]
            case 2: ["Monday. Who keeps resetting the week?"]
            case 3: ["Tuesday. Nobody talks about Tuesday. I respect that."]
            case 4: ["Wednesday. They put the middle right where you'd expect it."]
            case 5: ["Thursday. I peeked ahead. The weekend's close."]
            case 6: ["Friday. They want you to think the week is over."]
            default: ["Saturday. No plans. Exactly as planned."]
            }
        case .lunch: ["Lunch. My belly has been quiet. Too quiet.", "Go eat. I'll keep watch."]
        case .todoChecked: [
            "You're getting suspiciously good at this.",
            "The other to-dos are getting nervous.",
            "They'll be impressed.",
            "That's the end of that chapter.",
            "Nice. One less thing to overthink.",
        ]
        case .allTodosDone: ["The list is empty. Too empty.", "All done. You've earned a quiet evening."]
        case .preview: ["Hello. Don't mind me. I'm just reading."]
        case .headsUp: [
            "Bookmark that thought. Something's coming up.",
            "Plot twist incoming.",
            "Psst. Heads up.",
        ]
        }
    }
}

/// What the pet is saying right now: a line in the bubble while the menu is closed, or a small
/// second bubble beside her (to-dos, Settings, heads-ups). Both type themselves out, and each stays until
/// the mouse comes near her (`noticeMouse`), then goes away on its own, so a line said while you're
/// looking elsewhere waits for you.
@Observable
final class ChatterStore {
    /// Shown in the bubble when nothing else is (no menu, reminder, greeting or timer). Clicking closes it.
    var line: String? {
        didSet { if line != oldValue { onChange?() } }
    }
    /// When `line` started typing.
    private(set) var lineStart = Date.distantPast

    /// The small bubble beside the pet.
    private(set) var pageLine: String? {
        didSet { if pageLine != oldValue { onChange?() } }
    }
    private(set) var pageLineStart = Date.distantPast

    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private var lineID = 0
    @ObservationIgnored private var pageLineID = 0
    /// Whether the mouse has come near since the line was said, which starts its fade countdown.
    @ObservationIgnored private var lineNoticed = false
    @ObservationIgnored private var pageLineNoticed = false

    /// How long a line stays once it's been noticed and fully typed.
    static let lineDuration: TimeInterval = 7
    static let pageLineDuration: TimeInterval = 4

    /// Whether a line is waiting for the mouse to come near.
    var isWaitingToBeNoticed: Bool {
        (line != nil && !lineNoticed) || (pageLine != nil && !pageLineNoticed)
    }

    func say(_ text: String) {
        lineID += 1
        lineNoticed = false
        lineStart = Date()
        line = text
    }

    func sayAbovePage(_ text: String) {
        pageLineID += 1
        pageLineNoticed = false
        pageLineStart = Date()
        pageLine = text
    }

    func clearPageLine() {
        pageLineID += 1
        pageLine = nil
    }

    /// The mouse is over her or one of her bubbles: waiting lines start counting down, from when they're fully typed.
    func noticeMouse() {
        if let line, !lineNoticed {
            lineNoticed = true
            let id = lineID
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.timeLeft(line, from: lineStart, staying: Self.lineDuration)) { [weak self] in
                if self?.lineID == id { self?.line = nil }
            }
        }
        if let pageLine, !pageLineNoticed {
            pageLineNoticed = true
            let id = pageLineID
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.timeLeft(pageLine, from: pageLineStart, staying: Self.pageLineDuration)) { [weak self] in
                if self?.pageLineID == id { self?.pageLine = nil }
            }
        }
    }

    private static func timeLeft(_ text: String, from start: Date, staying: TimeInterval) -> TimeInterval {
        max(0, start.addingTimeInterval(TypewriterText.typingTime(text)).timeIntervalSinceNow) + staying
    }
}

/// Text that types itself out a letter at a time. The hidden letters are drawn clear, so the text
/// wraps and sizes as the whole line from the start and the bubble never grows.
struct TypewriterText: View {
    let text: String
    let start: Date

    static let perLetter: TimeInterval = 0.03

    static func typingTime(_ text: String) -> TimeInterval {
        Double(text.count) * perLetter
    }

    var body: some View {
        let done = Date().timeIntervalSince(start) >= Self.typingTime(text)
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: done)) { context in
            let shown = Int(context.date.timeIntervalSince(start) / Self.perLetter)
            Text(revealed(done ? text.count : min(max(shown, 0), text.count)))
        }
    }

    private func revealed(_ count: Int) -> AttributedString {
        let split = text.index(text.startIndex, offsetBy: count)
        var hidden = AttributedString(String(text[split...]))
        hidden.foregroundColor = .clear
        return AttributedString(String(text[..<split])) + hidden
    }
}

/// A heads-up in the main bubble, laid out like a due reminder: "🔔 In 5 min · 8:20 PM" over the message.
/// Clicking the bubble closes it. Her personality's line goes in the side bubble.
struct BubbleHeadsUp<Join: View>: View {
    let reminder: Reminder
    /// How many more are waiting after this one, like the due reminder's "· N more".
    let moreCount: Int
    /// A meeting's Join button, under the message.
    @ViewBuilder var join: Join

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
            join
            Text(moreCount > 0 ? "Click to close · \(moreCount) more" : "Click to close")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .opacity(0.55)
        }
    }
}

/// The line in the bubble while the menu is closed.
struct BubbleChatterLine: View {
    let text: String
    let start: Date

    var body: some View {
        WrappingWidth(maxWidth: 180) {
            TypewriterText(text: text, start: start)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
        }
    }
}

/// The small bubble beside the pet (in its own window), with its tail pointing at her.
struct BubblePageLine: View {
    let text: String
    let start: Date
    /// Her on the left, so the tail points left; false when the bubble sits on her left.
    let tailOnLeft: Bool

    private static let tailWidth: CGFloat = 6

    var body: some View {
        WrappingWidth(maxWidth: 170) {
            TypewriterText(text: text, start: start)
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
