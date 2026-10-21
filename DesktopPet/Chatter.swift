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
    case lunch
    /// In the small bubble above the To-dos page.
    case todoChecked, allTodosDone
    /// In the small bubble beside the pet, when picking a personality in Settings.
    case preview
    /// In the side bubble (shortly after the hop), a few minutes before a reminder (Settings → Reminders), while the main bubble
    /// shows the reminder itself, so the lines never say when it is.
    case headsUp
    /// In the side bubble (shortly after the hop) when any reminder comes due, meetings included, so the lines fit any reminder.
    case reminderDue
    /// In the side bubble after picking a color (Clipboard). Lines may say `{color}`, `{Color}` or `{COLOR}`, filled
    /// with its everyday name; `ownColorPicked` is for a color that matches one of hers.
    case colorPicked, ownColorPicked
    /// In the side bubble after taking a screenshot (Clipboard).
    case screenshot

    fileprivate var key: String {
        switch self {
        case .lunch: "lunch"
        case .todoChecked: "todoChecked"
        case .allTodosDone: "allTodosDone"
        case .preview: "preview"
        case .headsUp: "headsUp"
        case .reminderDue: "reminderDue"
        case .colorPicked: "colorPicked"
        case .ownColorPicked: "ownColorPicked"
        case .screenshot: "screenshot"
        }
    }
}

enum Chatter {
    /// A line for `moment`. Lines are dealt from a shuffled deck (saved across launches),
    /// so none repeats until all of that moment's lines have shown.
    /// `color` fills in a `.colorPicked` line's `{color}` ("sky blue"), `{Color}` ("Sky blue") or `{COLOR}` ("SKY BLUE").
    static func line(_ moment: ChatterMoment, _ personality: Personality, color: String) -> String {
        line(moment, personality)
            .replacingOccurrences(of: "{color}", with: color)
            .replacingOccurrences(of: "{Color}", with: color.prefix(1).uppercased() + color.dropFirst())
            .replacingOccurrences(of: "{COLOR}", with: color.uppercased())
    }

    static func line(_ moment: ChatterMoment, _ personality: Personality) -> String {
        deal("chatter.deck.\(personality.rawValue).\(moment.key)", from: lines(moment, personality))
    }

    /// The next card in a shuffled deck saved under `key` that `fits`; a card that doesn't fit yet stays in the deck
    /// for later. A new deck starts once nothing left fits, never with the card just dealt.
    private static func deal(_ key: String, from all: [String], where fits: (String) -> Bool = { _ in true }) -> String {
        let defaults = UserDefaults.standard
        let last = defaults.string(forKey: key + ".last")
        // Lines removed since the deck was saved are dropped.
        var deck = (defaults.stringArray(forKey: key) ?? []).filter(all.contains)
        if !deck.contains(where: fits) {
            deck = all.shuffled()
            if let first = deck.firstIndex(where: fits), deck[first] == last, deck.filter(fits).count > 1 {
                deck.append(deck.remove(at: first))
            }
        }
        guard let index = deck.firstIndex(where: fits) else { return all.first ?? "" }
        let card = deck.remove(at: index)
        defaults.set(deck, forKey: key)
        defaults.set(card, forKey: key + ".last")
        return card
    }

    // MARK: Greeting

    /// Her line beside the morning greeting: a greeting ("It's {dayName}!") and a saying that fits the time and day,
    /// each from its own deck, so the pairs keep changing. (Natalie chose this over whole lines per weekday and
    /// time of day: 5 greetings and 10 sayings each, 5 for any time and 5 for a time of day, the weekend or a day.)
    /// `{dayName}`/`{DAYNAME}` and `{timeOfDay}`/`{TimeOfDay}`/`{TIMEOFDAY}` are filled in.
    static func greetingLine(_ personality: Personality, at date: Date = Date()) -> String {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)
        let time: GreetingFit = switch calendar.component(.hour, from: date) {
        case ..<12: .morning
        case ..<17: .afternoon
        default: .evening
        }
        let sayings = greetingSayings(personality)
        let key = "chatter.deck.\(personality.rawValue).greeting"
        let greeting = deal(key, from: greetingOpeners(personality))
        let saying = deal(key + "Saying", from: sayings.map(\.text)) { text in
            switch sayings.first(where: { $0.text == text })?.fit ?? .any {
            case .any: true
            case .day(let day): day == weekday
            case .weekend: weekday == 1 || weekday == 7
            case let fit: fit == time
            }
        }
        let timeOfDay = switch time {
        case .morning: "morning"
        case .afternoon: "afternoon"
        default: "evening"
        }
        let dayName = date.formatted(.dateTime.weekday(.wide))
        // One sentence run together, so it reads as one thought (Natalie tried each half on its own line).
        return "\(greeting) \(saying)"
            .replacingOccurrences(of: "{dayName}", with: dayName)
            .replacingOccurrences(of: "{DAYNAME}", with: dayName.uppercased())
            .replacingOccurrences(of: "{timeOfDay}", with: timeOfDay)
            .replacingOccurrences(of: "{TimeOfDay}", with: timeOfDay.capitalized)
            .replacingOccurrences(of: "{TIMEOFDAY}", with: timeOfDay.uppercased())
    }

    /// When a greeting saying fits. `day` is a `Calendar` weekday (1 = Sunday).
    private enum GreetingFit: Equatable {
        case any, morning, afternoon, evening, weekend
        case day(Int)
    }

    /// Greetings fit any time. None of Sassy's is cheery, so one can come before her Monday complaint.
    private static func greetingOpeners(_ personality: Personality) -> [String] {
        switch personality {
        case .bubbly: ["Happy {dayName}!", "Hiii!", "Heyyy! You're here!", "GOOOOD {TIMEOFDAY}!", "{dayName}! It's {DAYNAME}!"]
        case .sassy: ["Good {timeOfDay}.", "Ah, {dayName}.", "Oh, it's {dayName}.", "{dayName}, is it?", "I've arrived."]
        // The colons make the saying read like the news in a memo.
        case .boss: ["Good {timeOfDay}, team.", "Happy {dayName}, team.", "Ah, my star employee.", "{dayName} briefing:", "Quick {timeOfDay} update:"]
        case .dark: ["{TimeOfDay}.", "Ah. {dayName}.", "You're back. Good.", "Hello from the quiet corner.", "It's {dayName}. I checked."]
        }
    }

    /// Sayings never name the day, since some greetings already do, and must read well after every greeting.
    private static func greetingSayings(_ personality: Personality) -> [(text: String, fit: GreetingFit)] {
        switch personality {
        case .bubbly: [
            ("Lowkey a great day already.", .any),
            ("{TimeOfDay}s go hard.", .any),
            ("Zoomies, anyone?", .any),
            ("Big day? Small day? Let's GO!", .any),
            ("Seeing you? Best part of my day.", .any),
            ("Power-up first? (Coffee.)", .morning),
            ("Snack time? SNACK TIME?", .afternoon),
            ("Weekend mode: on.", .weekend),
            ("We're SO back!", .day(2)),
            ("We made it!", .day(6)),
        ]
        case .sassy: [
            ("Looking for me?", .any),
            ("Try not to be dazzled.", .any),
            ("Today had better impress me.", .any),
            ("You and me? Iconic.", .any),
            ("Let's give them something to talk about.", .any),
            ("The day may now begin.", .morning),
            ("Evenings were made for me.", .evening),
            ("A day of rest. I'm a natural.", .weekend),
            ("The audacity of this day.", .day(2)),
            ("Finally, an event worthy of me.", .day(6)),
        ]
        case .boss: [
            ("Today's agenda: greatness.", .any),
            ("Profits are up. I checked.", .any),
            ("Your dedication has been noted.", .any),
            ("Let's circle back to excellence.", .any),
            ("Morale is at an all-time high.", .any),
            ("Coffee is a business expense.", .morning),
            ("Afternoon snacks are fully funded.", .afternoon),
            ("Company-wide day off. I signed it.", .weekend),
            ("New week, new goals.", .day(2)),
            ("Let's close out the week strong.", .day(6)),
        ]
        case .dark: [
            ("I've been reading. Don't ask what.", .any),
            ("Tea? A book? Both?", .any),
            ("They haven't noticed us yet. Perfect.", .any),
            ("Let's take it slow.", .any),
            ("This is my favorite time to think.", .any),
            ("Coffee first. Talking later.", .morning),
            ("The best books are read at night.", .evening),
            ("No plans. Exactly as planned.", .weekend),
            ("Who keeps resetting the week?", .day(2)),
            ("They want you to think the week is over.", .day(6)),
        ]
        }
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
        case .reminderDue: ["It's time! It's TIME!", "Ding ding! Let's GO!", "You've got this! I'll be right here!"]
        case .colorPicked: ["{COLOR}! Such a vibe!", "Whoa, {color}! Great pick!", "Nice! {Color} acquired."]
        case .ownColorPicked: ["Hey! That's MY color! Good pick!"]
        case .screenshot: ["Say cheese!", "Snap! Saved for later!", "Got it! Great shot!"]
        }
    }

    private static func sassy(_ moment: ChatterMoment) -> [String] {
        switch moment {
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
        case .reminderDue: [
            "Your reminder, delivered with style.",
            "It's time. I reminded you, naturally.",
            "Don't keep it waiting. Only I get to do that.",
        ]
        case .colorPicked: ["Ah, {color}. Bold choice.", "{Color}. I'd look stunning in it.", "{Color}? Approved."]
        case .ownColorPicked: ["My color. Obviously the best one."]
        case .screenshot: ["Did you get my good side?", "Captured. Hopefully I was in it.", "Another masterpiece for the archives."]
        }
    }

    /// Topsy as the CEO of a tiny company where you're the star employee. Management approves of everything you do;
    /// never a real boss (no deadlines, "back to work" or working late).
    private static func boss(_ moment: ChatterMoment) -> [String] {
        switch moment {
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
        case .reminderDue: ["Action item: due now.", "Showtime. Let's make it happen.", "Go get 'em. I'll hold your calls."]
        case .colorPicked: [
            "{Color}. Very on-brand.",
            "{Color} has been approved by the design team.",
            "{Color}. Let's put it in the brand guide.",
        ]
        case .ownColorPicked: ["Ah, the company colors."]
        case .screenshot: [
            "Documented. Great for the slide deck.",
            "Saved for the quarterly report.",
            "Excellent. Put that in the meeting notes.",
        ]
        }
    }

    /// A chill, cozy old soul who loves reading and tea, deadpan and a little off the wall, with a running bit about "they".
    /// Playfully mysterious but warm, never wary of you; no detective or fortune-teller lines.
    private static func dark(_ moment: ChatterMoment) -> [String] {
        switch moment {
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
        case .reminderDue: ["Right on schedule. Suspiciously.", "And so, it begins.", "Good luck. I'll hold your spot."]
        case .colorPicked: ["{Color}. Interesting choice.", "{Color}. I knew you'd pick that one.", "{Color}. Good color for a book cover."]
        case .ownColorPicked: ["That's my color. I'm flattered."]
        case .screenshot: ["A moment, saved. Like a bookmark.", "Got it. Some things are worth remembering.", "Saved. They'll never know."]
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
