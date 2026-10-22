import Foundation
import Observation
import SwiftUI

/// How the pet talks, picked as Chatter in Settings; every chatter line comes in each one's voice.
enum Personality: String, CaseIterable {
    // Saved by these raw values; Bubbly and Dark were renamed Upbeat and Deadpan in Settings only.
    case bubbly, sassy, boss, dark, butler

    var title: String {
        switch self {
        case .bubbly: "Upbeat"
        case .sassy: "Sassy"
        case .boss: "Boss"
        case .dark: "Deadpan"
        case .butler: "Butler"
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
    /// A repeating reminder coming due: these routine lines are mixed in with her usual `reminderDue` ones, so a daily
    /// reminder only hears one now and then.
    case repeatingDue
    /// The day's last reminder coming due, when another already came due today ("the last one" is odd after only one).
    /// Wins over `repeatingDue`, since it tells you something.
    case lastDue
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
        case .repeatingDue: "repeatingDue"
        case .lastDue: "lastDue"
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
        let timeOfDay = switch time {
        case .morning: "morning"
        case .afternoon: "afternoon"
        default: "evening"
        }
        func filled(_ line: String) -> String {
            let dayName = date.formatted(.dateTime.weekday(.wide))
            return line
                .replacingOccurrences(of: "{dayName}", with: dayName)
                .replacingOccurrences(of: "{DAYNAME}", with: dayName.uppercased())
                .replacingOccurrences(of: "{timeOfDay}", with: timeOfDay)
                .replacingOccurrences(of: "{TimeOfDay}", with: timeOfDay.capitalized)
                .replacingOccurrences(of: "{TIMEOFDAY}", with: timeOfDay.uppercased())
        }
        // A special day gets its own whole line, with no greeting before it, so it feels made for the day.
        if let day = SpecialDay(date) { return filled(specialLine(day, personality)) }
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
        return filled("\(greeting) \(saying)")
    }

    /// One line per personality for each special day, said in place of the greeting line (Natalie wrote these
    /// 2026-10-22). Lines never mention chocolate, since dogs can't eat it.
    private static func specialLine(_ day: SpecialDay, _ personality: Personality) -> String {
        switch personality {
        case .butler:
            switch day {
            case .newYearsDay: "A happy New Year to you. Have you settled on your resolutions?"
            case .newYearsEve: "The last day of the year. Do celebrate responsibly."
            case .valentinesDay: "Happy Valentine's Day. You are, as ever, much appreciated."
            case .leapDay: "Happy Leap Day. An extra day, to use as you see fit."
            case .stPatricksDay: "Happy St. Patrick's Day. I trust you're wearing green."
            case .aprilFools: "Good {timeOfDay}. I regret to inform you the tea is now soup. It has always been soup."
            case .easter: "Happy Easter. Might I suggest a hot cross bun?"
            case .fourthOfJuly: "A happy Fourth of July. Fireworks this evening, I expect."
            case .halloween: "Happy Halloween. I've dressed as a butler. Very convincing, I'm told."
            case .thanksgiving: "Happy Thanksgiving. I'm thankful for you, if I may say so."
            case .decemberFirst: "Welcome to December. Have you started your advent calendar?"
            case .christmasEve: "A good Christmas Eve to you. All is calm, as it should be."
            case .christmas: "A very merry Christmas. Tea by the tree, perhaps?"
            case .fridayThe13th: "Friday the 13th. I've taken the usual precautions."
            }
        case .bubbly:
            switch day {
            case .newYearsDay: "HAPPY NEW YEAR! New year, new side quests!"
            case .newYearsEve: "New Year's Eve! Midnight snacks? MIDNIGHT SNACKS!"
            case .valentinesDay: "Happy Valentine's Day! You're my favorite human. No cap."
            case .leapDay: "LEAP DAY! Bonus day unlocked!"
            case .stPatricksDay: "Happy St. Patrick's Day! Feeling lucky? I'm feeling LUCKY!"
            case .aprilFools: "Breaking news: coffee is free now! \u{2026}April Fools. Sorry. I'm sad too."
            case .easter: "Happy Easter! Did the Easter Bunny bring treats?!"
            case .fourthOfJuly: "Happy Fourth of July! Fireworks go BOOM! (I'll be under the bed.)"
            case .halloween: "Happy Halloween! Trick or treat? TREAT. Always treat!"
            case .thanksgiving: "Happy Thanksgiving! Grateful for you. And turkey. Mostly you!"
            case .decemberFirst: "It's DECEMBER! Advent calendar time! Is there a treat behind every door?!"
            case .christmasEve: "It's Christmas Eve! Is it tomorrow yet? Is it NOW?"
            case .christmas: "MERRY CHRISTMAS! The wrapping paper is MINE!"
            case .fridayThe13th: "Friday the 13th?! Lucky number 13! Right? RIGHT?"
            }
        // Punnier than his everyday lines (Natalie found the puns funnier for rare days).
        case .boss:
            switch day {
            case .newYearsDay: "Happy New Year, team. Let's set some big Q1 goals."
            case .newYearsEve: "Happy New Year's Eve. Let's close out the fiscal year with a bang."
            case .valentinesDay: "Happy Valentine's Day. You're the heart of this company."
            case .leapDay: "Happy Leap Day. Profits are taking a leap too."
            case .stPatricksDay: "Happy St. Patrick's Day. Everything's coming up green. Like our profits."
            case .aprilFools: "Exciting news, team: we've acquired the moon. The board is thrilled."
            case .easter: "Happy Easter. Our spring outlook? Egg-cellent."
            case .fourthOfJuly: "Happy Fourth of July. Let's make it a red, white and booming success."
            case .halloween: "Happy Halloween. Should we hold a costume contest?"
            case .thanksgiving: "Happy Thanksgiving. This year's results? Stuffed with success."
            case .decemberFirst: "Welcome to December, team. Be sure to book your days off."
            case .christmasEve: "Happy Christmas Eve. Out-of-office replies: activated."
            case .christmas: "Merry Christmas, team. Time for the gift exchange. Let's wrap this year up."
            case .fridayThe13th: "Friday the 13th. I had legal look into it. We're fine."
            }
        case .sassy:
            switch day {
            case .newYearsDay: "Happy New Year. My resolution? Change nothing. I'm already perfect."
            case .newYearsEve: "New Year's Eve. The ball drops tonight. My standards never do."
            case .valentinesDay: "Happy Valentine's Day. I'm everyone's valentine. You're welcome."
            case .leapDay: "An extra day this year? The world needed more of me."
            case .stPatricksDay: "Happy St. Patrick's Day. Pinch me and see what happens."
            case .aprilFools: "I've decided to be humble from now on. \u{2026}April Fools."
            case .easter: "Happy Easter. The best thing you'll find today is me."
            case .fourthOfJuly: "Happy Fourth of July. The fireworks are trying to upstage me. Rude."
            case .halloween: "Happy Halloween. Boo. Did I scare you? Of course I did."
            case .thanksgiving: "Happy Thanksgiving. Go on, say you're thankful for me."
            case .decemberFirst: "Finally, December. My gift list is very long. You'd better start shopping now."
            case .christmasEve: "Christmas Eve. I've been very good this year. Obviously."
            case .christmas: "Merry Christmas. Did you get everything on my list?"
            case .fridayThe13th: "Friday the 13th. Bad luck wouldn't dare come near me."
            }
        // The one place he gets properly spooky is Halloween.
        case .dark:
            switch day {
            case .newYearsDay: "Happy New Year. I resolve to read more. I always do."
            case .newYearsEve: "New Year's Eve. I'll be asleep by midnight. Tell me how it ends."
            case .valentinesDay: "Happy Valentine's Day. Roses are red. Coffee is warm. You're my favorite. Don't tell the others."
            case .leapDay: "Leap Day. An extra day. Nobody knows where it comes from."
            case .stPatricksDay: "Happy St. Patrick's Day. I've looked for the pot of gold. Still looking."
            case .aprilFools: "Your chair is haunted. April Fools'. (Probably.)"
            case .easter: "Happy Easter. I hid an egg somewhere. I forgot where. That's part of the fun."
            case .fourthOfJuly: "Happy Fourth of July. They'll be setting off fireworks. I'll be under a blanket with a book."
            case .halloween: "Happy Halloween. Something is coming for you tonight. It says hi."
            case .thanksgiving: "Happy Thanksgiving. I'm thankful for coffee, quiet and you. Not in that order."
            case .decemberFirst: "December. The advent calendar is out. I opened door 24 first. No regrets."
            case .christmasEve: "Christmas Eve. Something's coming down the chimney tonight. They say it's normal."
            case .christmas: "Merry Christmas. I'll be by the fire with a good book. Join me."
            case .fridayThe13th: "Friday the 13th. Watch your step today. They're watching theirs."
            }
        }
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
        case .butler: ["A very good {timeOfDay}.", "Welcome back.", "{dayName}, as scheduled.", "Good {timeOfDay}. Right on time.", "How do you do?"]
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
            ("Coffee first. It's brew-siness as usual.", .morning),
            ("Afternoon snacks are fully funded.", .afternoon),
            ("Company-wide day off. I signed it.", .weekend),
            ("New week, new goals.", .day(2)),
            ("Let's close out the week strong.", .day(6)),
        ]
        case .dark: [
            ("I've been reading. Don't ask what.", .any),
            ("Coffee? A book? Both?", .any),
            ("They haven't noticed us yet. Perfect.", .any),
            ("Let's take it slow.", .any),
            ("This is my favorite time to think.", .any),
            ("Coffee first. Talking later.", .morning),
            ("The best books are read at night.", .evening),
            ("No plans. Exactly as planned.", .weekend),
            ("Who keeps resetting the week?", .day(2)),
            ("They want you to think the week is over.", .day(6)),
        ]
        case .butler: [
            ("Everything is in order.", .any),
            ("I trust you're well.", .any),
            ("I've kept everything just as you left it.", .any),
            ("A pleasure, as always.", .any),
            ("I'm right here if you need anything.", .any),
            ("The day has been prepared.", .morning),
            ("Afternoon tea, perhaps?", .afternoon),
            ("A day of leisure, if you'd like.", .weekend),
            ("A fresh week, freshly pressed.", .day(2)),
            ("The week draws to a close. Splendid.", .day(6)),
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
        if moment == .repeatingDue {
            return lines(.reminderDue, personality) + ownLines(.repeatingDue, personality)
        }
        return ownLines(moment, personality)
    }

    private static func ownLines(_ moment: ChatterMoment, _ personality: Personality) -> [String] {
        switch personality {
        case .bubbly: bubbly(moment)
        case .sassy: sassy(moment)
        case .boss: boss(moment)
        case .dark: dark(moment)
        case .butler: butler(moment)
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
        case .repeatingDue: ["Our thing! It's time for our thing!", "Same time, same us!", "This one's tradition!"]
        case .lastDue: ["Last one today! Big finish!", "Final boss of the day!", "Last one! Let's finish strong!"]
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
        case .repeatingDue: ["Like clockwork. Like me.", "Again? I'll allow it.", "A classic. It never goes out of style."]
        case .lastDue: ["The grand finale. Make it count.", "Saving the best for last, I see.", "The final act. Hold your applause."]
        case .colorPicked: ["Ah, {color}. Bold choice.", "{Color}. I'd look stunning in it.", "{Color}? Approved."]
        case .ownColorPicked: ["My color. Obviously the best one."]
        case .screenshot: ["Did you get my good side?", "Captured. Hopefully I was in it.", "Another masterpiece for the archives."]
        }
    }

    /// Topsy as the CEO of a tiny company where you're the star employee. Management approves of everything you do;
    /// never a real boss (no deadlines, "back to work" or working late).
    private static func boss(_ moment: ChatterMoment) -> [String] {
        switch moment {
        case .lunch: ["Lunch break approved. Let's taco 'bout it.", "Lunch is now a mandatory meeting."]
        case .todoChecked: [
            "Now that's synergy.",
            "Impact player!",
            "Huge win for the team.",
            "That boosts morale!",
            "Great work! I'll tell the shareholders!",
        ]
        case .allTodosDone: ["All checked off. That's some real check-cellence.", "Every item delivered. The board is speechless."]
        case .preview: ["Welcome aboard! Glad to have you on the team."]
        case .headsUp: [
            "Per my last email: something's coming up.",
            "Quick sync incoming.",
            "Calendar update from management.",
        ]
        case .reminderDue: ["Action item: due now.", "Showtime. Let's make it happen.", "Go get 'em. I'll hold your calls."]
        case .repeatingDue: ["A standing item. Love the consistency.", "Like clockwork. That's company culture.", "Back by popular demand."]
        case .lastDue: ["Final item on today's agenda.", "Last action item. Then we're adjourned.", "Closing out today's agenda with this one."]
        case .colorPicked: [
            "{Color}. Very on-brand.",
            "{Color} has been approved by the design team.",
            "{Color}. A hue-ge win.",
        ]
        case .ownColorPicked: ["Ah, the company colors."]
        case .screenshot: [
            "Documented. Great for the slide deck.",
            "Saved for the quarterly report.",
            "Excellent. Put that in the meeting notes.",
        ]
        }
    }

    /// A chill, cozy old soul who loves reading and coffee, deadpan and a little off the wall, with a running bit about "they".
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
        case .repeatingDue: ["This again. It's tradition now.", "Same time. They must be watching.", "The ritual continues."]
        case .lastDue: ["This is the last one. They've run out of ideas.", "Last one. Then nothing. Perfect.", "The final chapter. For today."]
        case .colorPicked: ["{Color}. Interesting choice.", "{Color}. I knew you'd pick that one.", "{Color}. Good color for a book cover."]
        case .ownColorPicked: ["That's my color. I'm flattered."]
        case .screenshot: ["A moment, saved. Like a bookmark.", "Got it. Some things are worth remembering.", "Saved. They'll never know."]
        }
    }

    /// Dignified, overly formal and polite, with dry understatement; loves tea. Never "sir" or "madam" (or "master"),
    /// never servile, and never promises to do things Topsy can't.
    private static func butler(_ moment: ChatterMoment) -> [String] {
        switch moment {
        case .lunch: ["Might I suggest luncheon?", "Would you care for some tea and crumpets?"]
        case .todoChecked: [
            "Very good.",
            "Impeccably done.",
            "Splendid. One less on the list.",
            "Handled, with dignity.",
            "Another one, neatly concluded.",
        ]
        case .allTodosDone: ["The list is clear. Splendid work.", "Not a single item remains. Most impressive."]
        case .preview: ["At your service."]
        case .headsUp: [
            "Pardon the interruption. Something's coming up.",
            "If I may, something is on the schedule.",
            "A gentle reminder approaches.",
        ]
        case .reminderDue: ["It's time. Shall we?", "Your reminder, as requested.", "The appointed hour has arrived."]
        case .repeatingDue: ["Right on schedule, as ever.", "Your usual obligation.", "The customary appointment."]
        case .lastDue: ["The last matter of the day.", "And now, the final engagement of the day.", "The day's last item, if I may."]
        case .colorPicked: ["{Color}. An excellent selection.", "Ah, {color}. Very refined.", "{Color}. Noted for the records."]
        case .ownColorPicked: ["The very shade of my coat. How flattering."]
        case .screenshot: ["Captured, and filed away.", "Preserved for posterity.", "A fine picture. It's on your clipboard."]
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

/// A day that gets its own greeting line: a short list of widely celebrated (and US) holidays Natalie picked,
/// plus December 1 for the start of the advent countdown and Friday the 13th. Solemn days are left out on purpose.
enum SpecialDay {
    case newYearsDay, newYearsEve, valentinesDay, leapDay, stPatricksDay, aprilFools, easter, fourthOfJuly
    case halloween, thanksgiving, decemberFirst, christmasEve, christmas, fridayThe13th

    init?(_ date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month, .day, .weekday], from: date)
        guard let year = parts.year, let month = parts.month, let day = parts.day, let weekday = parts.weekday else { return nil }
        switch (month, day) {
        case (1, 1): self = .newYearsDay
        case (12, 31): self = .newYearsEve
        case (2, 14): self = .valentinesDay
        case (2, 29): self = .leapDay
        case (3, 17): self = .stPatricksDay
        case (4, 1): self = .aprilFools
        case (7, 4): self = .fourthOfJuly
        case (10, 31): self = .halloween
        case (12, 1): self = .decemberFirst
        case (12, 24): self = .christmasEve
        case (12, 25): self = .christmas
        // The fourth Thursday of November (US).
        case (11, 22...28) where weekday == 5: self = .thanksgiving
        case (_, 13) where weekday == 6: self = .fridayThe13th
        default:
            let easter = Self.easter(in: year)
            guard month == easter.month, day == easter.day else { return nil }
            self = .easter
        }
    }

    /// Western Easter Sunday, by the anonymous Gregorian algorithm.
    static func easter(in year: Int) -> (month: Int, day: Int) {
        let a = year % 19, b = year / 100, c = year % 100
        let d = b / 4, e = b % 4, f = (b + 8) / 25, g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4, k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = (h + l - 7 * m + 114) % 31 + 1
        return (month, day)
    }

    /// Whole days until Christmas, from December 1 to 24, for the greeting's countdown; nil otherwise.
    static func daysUntilChristmas(from date: Date, calendar: Calendar = .current) -> Int? {
        let parts = calendar.dateComponents([.month, .day], from: date)
        guard parts.month == 12, let day = parts.day, day <= 24 else { return nil }
        return 25 - day
    }
}
