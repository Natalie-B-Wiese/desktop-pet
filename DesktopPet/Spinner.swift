import Foundation
import Observation

struct SpinnerOption: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String
}

/// The Spinner game: a list of options, saved across launches, and a highlight that runs down the list,
/// slows down and stops on a random one.
@Observable
final class SpinnerStore {
    private(set) var options: [SpinnerOption] = []
    /// The option the highlight is on: moving while spinning, then the pick once it stops.
    private(set) var highlightedID: SpinnerOption.ID?
    private(set) var isSpinning = false

    /// Called with the pick once the highlight stops.
    @ObservationIgnored var onPicked: ((String) -> Void)?

    static let maxOptions = 10
    static let maxLength = 40
    private static let storageKey = "games.spinner.options"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode([SpinnerOption].self, from: data) {
            options = saved
        }
    }

    var canSpin: Bool { !isSpinning && options.count >= 2 }

    /// Adds an option at the bottom as soon as something is typed on the blank row. Keeps the
    /// blank row's ID so the row being typed on stays the same view.
    func add(id: SpinnerOption.ID, text: String) {
        guard options.count < Self.maxOptions else { return }
        options.append(SpinnerOption(id: id, text: String(text.prefix(Self.maxLength))))
        save()
    }

    /// Saves edits as they're typed.
    func update(_ id: SpinnerOption.ID, text: String) {
        guard let index = options.firstIndex(where: { $0.id == id }) else { return }
        options[index].text = String(text.prefix(Self.maxLength))
        save()
    }

    /// Once an option is done being typed on: trims it, or deletes it if it was emptied.
    func tidy(_ id: SpinnerOption.ID) {
        guard let option = options.first(where: { $0.id == id }) else { return }
        let trimmed = option.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            delete(id)
        } else if trimmed != option.text {
            update(id, text: trimmed)
        }
    }

    func delete(_ id: SpinnerOption.ID) {
        options.removeAll { $0.id == id }
        if highlightedID == id { highlightedID = nil }
        save()
    }

    /// Picks the winner first, then runs the highlight down the list (a lap or more) to land on it,
    /// fast at first and slowing to a stop, about 2–3 seconds in all.
    func spin() {
        guard canSpin else { return }
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
                guard options.count == count else { break }
                highlightedID = options[(start + step) % count].id
            }
            guard let self else { return }
            isSpinning = false
            if let id = highlightedID, let pick = options.first(where: { $0.id == id }) {
                onPicked?(pick.text)
            }
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(options) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
