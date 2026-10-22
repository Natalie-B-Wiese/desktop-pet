import Foundation
import Observation

/// The Number game: a random whole number between two ends (saved as typed).
/// The answer flickers through random ones for about half a second before it settles.
@Observable
final class NumberGame {
    var minText: String {
        didSet { UserDefaults.standard.set(minText, forKey: Self.minKey) }
    }
    var maxText: String {
        didSet { UserDefaults.standard.set(maxText, forKey: Self.maxKey) }
    }
    /// What the big answer shows: flickering while rolling, then the pick. Nil before the first roll.
    private(set) var shown: String?
    private(set) var isRolling = false
    /// Why the range can't be rolled, shown in grey under the boxes.
    private(set) var problem: String?

    static let maxLength = 9
    private static let minKey = "games.number.min"
    private static let maxKey = "games.number.max"

    init() {
        minText = UserDefaults.standard.string(forKey: Self.minKey) ?? "1"
        maxText = UserDefaults.standard.string(forKey: Self.maxKey) ?? "100"
    }

    /// A whole number from min to max. If min is bigger than max, the boxes quietly swap first.
    func roll() {
        guard !isRolling else { return }
        guard var low = Self.number(minText), var high = Self.number(maxText) else {
            problem = minText.trimmingCharacters(in: .whitespaces).isEmpty || maxText.trimmingCharacters(in: .whitespaces).isEmpty
                ? "Fill in both ends" : "Whole numbers only"
            return
        }
        problem = nil
        if low > high {
            (low, high) = (high, low)
            (minText, maxText) = (maxText, minText)
        }
        let pick = Int.random(in: low...high)
        isRolling = true
        Task { @MainActor [weak self] in
            await Flicker.run(to: pick.formatted(), frame: { _ in Int.random(in: low...high).formatted() }) { self?.shown = $0 }
            self?.isRolling = false
        }
    }

    /// A whole number as typed, allowing a minus sign and thousands commas.
    private static func number(_ text: String) -> Int? {
        Int(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ""))
    }
}

/// A game that picks one of a few answers, like the Coin (Heads, Tails) or rock, paper, scissors,
/// flickering through them for about half a second first.
@Observable
final class RandomPick {
    let answers: [String]
    /// Nil before the first pick.
    private(set) var shown: String?
    private(set) var isPicking = false

    init(_ answers: [String]) {
        self.answers = answers
    }

    func pick() {
        guard !isPicking else { return }
        let answers = answers
        isPicking = true
        Task { @MainActor [weak self] in
            await Flicker.run(to: answers.randomElement()!, frame: { answers[$0 % answers.count] }) { self?.shown = $0 }
            self?.isPicking = false
        }
    }
}

/// The games' half-second flicker before an answer settles.
enum Flicker {
    /// Shows `frame(n)` ten times, 0.05s apart, then `final`.
    @MainActor
    static func run(to final: String, frame: (Int) -> String, show: (String) -> Void) async {
        for n in 0..<10 {
            show(frame(n))
            try? await Task.sleep(for: .seconds(0.05))
        }
        show(final)
    }
}

/// Ask Topsy: a Magic 8-Ball. She thinks for a moment, then answers in her personality's voice.
@Observable
final class AskGame {
    /// Her answer, typed out from `answerStart`. Nil before the first question and while she thinks.
    private(set) var answer: String?
    private(set) var answerStart = Date.distantPast
    private(set) var isThinking = false

    func ask() {
        guard !isThinking else { return }
        let last = answer
        answer = nil
        isThinking = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(0.7))
            guard let self else { return }
            // Never the same answer twice in a row, so asking again always looks like a new answer.
            let choices = Chatter.answers(AppPreferences.chatter).filter { $0 != last }
            answer = choices.randomElement()
            answerStart = Date()
            isThinking = false
        }
    }
}
