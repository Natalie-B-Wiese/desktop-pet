import Foundation
import Observation

/// Guess the Word (hangman without the hanging): Topsy thinks of a word, shown as blanks with its category,
/// and you guess letters. Six wrong letters (paw prints) and she wins. The current word stays until it's
/// finished, even if you leave the page; words are dealt from a saved shuffled deck, so none repeats until all have shown.
@Observable
final class WordGame {
    static let lives = 6

    private(set) var word = ""
    private(set) var category = ""
    private(set) var guessed: Set<Character> = []
    /// What she just said about your guess, typed out from `reactionStart`.
    private(set) var reaction: String?
    private(set) var reactionStart = Date.distantPast

    private static let deckKey = "games.word.deck"

    var misses: Int { guessed.filter { !word.contains($0) }.count }
    var isWon: Bool { !word.isEmpty && word.allSatisfy(guessed.contains) }
    var isLost: Bool { misses >= Self.lives }
    var isOver: Bool { isWon || isLost }

    func guess(_ letter: Character) {
        let letter = Character(letter.uppercased())
        guard !isOver, letter.isLetter, letter.isASCII, !guessed.contains(letter) else { return }
        guessed.insert(letter)
        let count = word.filter { $0 == letter }.count
        if isWon {
            say(Chatter.wordWon(AppPreferences.chatter, misses: misses))
        } else if isLost {
            say(Chatter.wordLost(AppPreferences.chatter, word: word))
        } else if count == 0 {
            say("No \(letter) in this one.")
        } else {
            say(count == 1 ? "Yes! There's \(Self.article(letter)) \(letter)!" : "Yes! \(count) \(letter)s!")
        }
    }

    /// Deals the first word when the page first opens (not at launch, so launching doesn't use up the deck).
    func dealIfNeeded() {
        if word.isEmpty { newWord() }
    }

    /// Plays `word` instead of the deck's next one, for testing.
    func play(_ word: String) {
        self.word = word.uppercased()
        category = Self.category(of: self.word) ?? "Test"
        guessed = []
        reaction = nil
    }

    /// The next word from the deck.
    func newWord() {
        let defaults = UserDefaults.standard
        var deck = (defaults.stringArray(forKey: Self.deckKey) ?? []).filter { Self.category(of: $0) != nil }
        if deck.isEmpty { deck = Self.words.flatMap(\.words).shuffled() }
        word = deck.removeFirst()
        defaults.set(deck, forKey: Self.deckKey)
        category = Self.category(of: word) ?? ""
        guessed = []
        reaction = nil
    }

    private func say(_ text: String) {
        reaction = text
        reactionStart = Date()
    }

    /// "an E", "a B".
    private static func article(_ letter: Character) -> String {
        "AEFHILMNORSX".contains(letter) ? "an" : "a"
    }

    private static func category(of word: String) -> String? {
        words.first { $0.words.contains(word) }?.category
    }

    /// Everyday, family-friendly words of 4–7 letters (7 is Natalie's limit; drafted by the agent for her to review).
    static let words: [(category: String, words: [String])] = [
        ("Animal", ["RABBIT", "PENGUIN", "TURTLE", "GIRAFFE", "MONKEY", "DOLPHIN", "KOALA", "ZEBRA", "HAMSTER", "PARROT", "OTTER", "PANDA"]),
        ("Food", ["PANCAKE", "COOKIE", "PIZZA", "BANANA", "CHEESE", "TACO", "MUFFIN", "NOODLES", "WAFFLE", "POPCORN", "PICKLE", "BAGEL"]),
        ("Around the house", ["PILLOW", "BLANKET", "TEAPOT", "CANDLE", "MIRROR", "LADDER", "BUCKET", "SOFA", "LAMP", "TOASTER", "TABLE", "CURTAIN"]),
        ("Nature", ["RAINBOW", "THUNDER", "PUDDLE", "CACTUS", "VOLCANO", "ISLAND", "MEADOW", "ACORN", "BLOSSOM", "RIVER", "PEBBLE", "BREEZE"]),
        ("Things that go", ["BICYCLE", "ROCKET", "TRAIN", "SCOOTER", "TRACTOR", "TRUCK", "WAGON", "SUBWAY", "KAYAK", "BALLOON", "CANOE", "TAXI"]),
    ]
}
