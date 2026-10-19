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
    /// Back after the Mac was asleep or locked for a while.
    case welcomeBack
    case lunch, lateNight
    /// In the small bubble above the To-dos page.
    case todoChecked, allTodosDone
    /// In the small bubble above Settings, when picking a personality.
    case preview

    fileprivate var key: String {
        switch self {
        case .morning: "morning"
        case .afternoon: "afternoon"
        case .evening: "evening"
        case .weekday(let day): "weekday\(day)"
        case .welcomeBack: "welcomeBack"
        case .lunch: "lunch"
        case .lateNight: "lateNight"
        case .todoChecked: "todoChecked"
        case .allTodosDone: "allTodosDone"
        case .preview: "preview"
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
        case .welcomeBack: [
            "You're back! I saved your seat.",
            "Oh hey, missed you.",
            "Welcome back. Coffee refill?",
            "You're back! Reminder: you're my favorite human.",
            "Welcome back. Vibe check: passed.",
        ]
        case .lunch: ["Lunch break? Asking for a friend.", "Food buff time."]
        case .lateNight: [
            "Tomorrow-you can handle the rest. They're great.",
            "You did so much today. Go rest.",
            "Logging off is self-care, actually.",
        ]
        case .todoChecked: [
            "That one never stood a chance.",
            "+10 XP!",
            "Task complete! Efficiency +1",
            "Ate. No crumbs.",
            "Another one handled.",
            "We love to see it.",
            "It's giving productive.",
            "I'd high-five you, but paws.",
        ]
        case .allTodosDone: ["Cleared the whole list? Iconic.", "You're the GOAT."]
        case .preview: ["Ready when you are."]
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
        case .welcomeBack: [
            "You left me. Alone. …I forgive you.",
            "Where were you?! The drama!",
            "I didn't miss you. (I did.)",
        ]
        case .lunch: ["Feed yourself. I need my human at full strength.", "Lunch. Something worthy of us, please."]
        case .lateNight: [
            "Even royalty needs beauty sleep. So do you.",
            "Still up? Bedtime is very glamorous, you know.",
        ]
        case .todoChecked: [
            "Clearly my influence.",
            "Not bad. I taught you that.",
            "Done? Of course. You have me.",
            "Another one. I'm a great motivator.",
            "I'll accept your thanks now.",
            "Impressive. Almost as impressive as me.",
            "Was there ever any doubt?",
            "Handled. Under my supervision.",
        ]
        case .allTodosDone: ["Flawless. I'd expect nothing less from my human.", "A clean list. We make a stunning team."]
        case .preview: ["Bow down. Kidding. Mostly."]
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

    /// The small bubble above the open page.
    private(set) var pageLine: String?

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
        withAnimation(.easeOut(duration: 0.2)) { pageLine = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.pageLineDuration) { [weak self] in
            guard let self, pageLineID == id else { return }
            withAnimation(.easeIn(duration: 0.4)) { self.pageLine = nil }
        }
    }

    func clearPageLine() {
        pageLineID += 1
        pageLine = nil
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
