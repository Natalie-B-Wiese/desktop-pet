import Foundation
import Observation

/// The Groups game: a list of items (names, tasks, anything; typed in like the Spinner's Custom list, saved
/// separately) dealt out at random into 2–6 even groups. The items flicker between groups for a moment before they settle.
/// The list can be long (up to 50); the page scrolls.
@Observable
final class GroupsStore {
    private(set) var items: [SpinnerOption] = []
    /// How many groups to make, saved.
    private(set) var groupCount: Int
    /// The groups made, or nil while editing the items.
    private(set) var groups: [[SpinnerOption]]?
    private(set) var isMaking = false

    static let maxItems = 50
    static let groupCounts = 2...6
    private static let itemsKey = "games.groups.items"
    private static let countKey = "games.groups.count"

    init() {
        let saved = UserDefaults.standard.integer(forKey: Self.countKey)
        groupCount = Self.groupCounts.contains(saved) ? saved : 2
        if let data = UserDefaults.standard.data(forKey: Self.itemsKey),
           let decoded = try? JSONDecoder().decode([SpinnerOption].self, from: data) {
            items = decoded
        }
    }

    /// Every group gets at least one item.
    var canMake: Bool { !isMaking && items.count >= groupCount }

    /// The next (+1) or previous (-1) number of groups, wrapping around.
    func stepGroupCount(by offset: Int) {
        guard !isMaking else { return }
        let counts = Array(Self.groupCounts)
        let index = counts.firstIndex(of: groupCount) ?? 0
        groupCount = counts[((index + offset) % counts.count + counts.count) % counts.count]
        UserDefaults.standard.set(groupCount, forKey: Self.countKey)
        if groups != nil { make() } // already showing groups: remake them with the new count
    }

    /// Shuffles the items and deals them out like cards, so group sizes differ by at most one.
    /// A few quick random deals flicker by first.
    func make() {
        guard canMake else { return }
        isMaking = true
        Task { @MainActor [weak self] in
            for _ in 0..<5 {
                guard let self else { return }
                groups = Self.deal(items, into: groupCount)
                try? await Task.sleep(for: .seconds(0.09))
            }
            guard let self else { return }
            groups = Self.deal(items, into: groupCount)
            isMaking = false
        }
    }

    /// Back to the list of items.
    func editItems() {
        guard !isMaking else { return }
        groups = nil
    }

    private static func deal(_ items: [SpinnerOption], into count: Int) -> [[SpinnerOption]] {
        var groups = Array(repeating: [SpinnerOption](), count: count)
        for (index, item) in items.shuffled().enumerated() { groups[index % count].append(item) }
        return groups
    }

    // MARK: - Editing items (like the Spinner's Custom list)

    /// Adds an item at the bottom as soon as something is typed on the blank row, keeping the blank row's ID.
    func add(id: SpinnerOption.ID, text: String) {
        guard items.count < Self.maxItems else { return }
        items.append(SpinnerOption(id: id, text: String(text.prefix(SpinnerStore.maxLength))))
        save()
    }

    func update(_ id: SpinnerOption.ID, text: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].text = String(text.prefix(SpinnerStore.maxLength))
        save()
    }

    /// Once an item is done being typed on: trims it, or deletes it if it was emptied.
    func tidy(_ id: SpinnerOption.ID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        let trimmed = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            delete(id)
        } else if trimmed != item.text {
            update(id, text: trimmed)
        }
    }

    func delete(_ id: SpinnerOption.ID) {
        items.removeAll { $0.id == id }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: Self.itemsKey)
        }
    }
}
