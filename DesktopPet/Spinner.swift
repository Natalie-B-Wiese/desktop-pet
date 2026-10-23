import Foundation
import Observation

struct SpinnerOption: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String
}

/// The Spinner's lists, stepped through with ‹ › in this order. Custom is yours; the others are locked presets.
enum SpinnerList: String, CaseIterable {
    case custom, coin, rps

    var title: String {
        switch self {
        case .custom: "Custom"
        case .coin: "Coin"
        case .rps: "RPS"
        }
    }

    /// A preset's options (made once, so their IDs never change), or nil for Custom.
    var preset: [SpinnerOption]? { Self.presets[self] }

    private static let presets: [SpinnerList: [SpinnerOption]] = [
        .coin: ["Heads", "Tails"].map { SpinnerOption(text: $0) },
        .rps: ["Rock", "Paper", "Scissors"].map { SpinnerOption(text: $0) },
    ]
}

/// The Spinner game: a list of options and a highlight that runs down it, slows down and stops on a random one.
/// The Custom list is typed in and saved across launches; Coin and RPS can't be edited.
@Observable
final class SpinnerStore {
    /// The list showing, saved so the page opens on it again.
    private(set) var list: SpinnerList
    /// Your own options, the Custom list.
    private(set) var custom: [SpinnerOption] = []
    /// The option the highlight is on: moving while spinning, then the pick once it stops.
    private(set) var highlightedID: SpinnerOption.ID?
    private(set) var isSpinning = false

    static let maxOptions = 10
    static let maxLength = 40
    private static let storageKey = "games.spinner.options"
    private static let listKey = "games.spinner.list"

    init() {
        list = UserDefaults.standard.string(forKey: Self.listKey).flatMap(SpinnerList.init) ?? .custom
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode([SpinnerOption].self, from: data) {
            custom = saved
        }
    }

    /// The options of the list showing.
    var options: [SpinnerOption] { list.preset ?? custom }

    var canSpin: Bool { !isSpinning && options.count >= 2 }

    /// The next (+1) or previous (-1) list, wrapping around.
    func stepList(by offset: Int) {
        guard !isSpinning else { return }
        let all = SpinnerList.allCases
        let index = all.firstIndex(of: list)!
        list = all[((index + offset) % all.count + all.count) % all.count]
        highlightedID = nil
        UserDefaults.standard.set(list.rawValue, forKey: Self.listKey)
    }

    /// Adds an option at the bottom of Custom as soon as something is typed on the blank row. Keeps the
    /// blank row's ID so the row being typed on stays the same view.
    func add(id: SpinnerOption.ID, text: String) {
        guard custom.count < Self.maxOptions else { return }
        custom.append(SpinnerOption(id: id, text: String(text.prefix(Self.maxLength))))
        save()
    }

    /// Saves edits as they're typed.
    func update(_ id: SpinnerOption.ID, text: String) {
        guard let index = custom.firstIndex(where: { $0.id == id }) else { return }
        custom[index].text = String(text.prefix(Self.maxLength))
        save()
    }

    /// Once an option is done being typed on: trims it, or deletes it if it was emptied.
    func tidy(_ id: SpinnerOption.ID) {
        guard let option = custom.first(where: { $0.id == id }) else { return }
        let trimmed = option.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            delete(id)
        } else if trimmed != option.text {
            update(id, text: trimmed)
        }
    }

    func delete(_ id: SpinnerOption.ID) {
        custom.removeAll { $0.id == id }
        if highlightedID == id { highlightedID = nil }
        save()
    }

    /// Picks the winner first, then runs the highlight down the list (a lap or more) to land on it,
    /// fast at first and slowing to a stop, about 2–3 seconds in all.
    func spin() {
        guard canSpin else { return }
        let options = options
        let count = options.count
        let start = highlightedID.flatMap { id in options.firstIndex { $0.id == id } } ?? -1
        let winner = Int.random(in: 0..<count)
        var steps = ((winner - start) % count + count) % count
        while steps < 16 { steps += count }

        isSpinning = true
        Task { @MainActor [weak self] in
            for step in 1...steps {
                let progress = Double(step) / Double(steps)
                try? await Task.sleep(for: .seconds(0.04 + 0.32 * pow(progress, 3)))
                guard let self else { return }
                highlightedID = options[(start + step) % count].id
            }
            self?.isSpinning = false
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(custom) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
