import Foundation
import Observation

struct SpinnerOption: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String
}

/// The Spinner's lists, stepped through with ‹ › in this order. To-dos is your unchecked to-dos, live; Coin and RPS
/// are presets; the three Custom lists, last, are yours. All but Custom are locked (to-dos are edited on the To-dos page).
/// The first Custom list keeps the old raw value `custom`, so a list saved before there were three still loads.
enum SpinnerList: String, CaseIterable {
    case todos, coin, rps, custom, custom2, custom3

    var isCustom: Bool { [.custom, .custom2, .custom3].contains(self) }
    var isLocked: Bool { !isCustom }

    var title: String {
        switch self {
        case .todos: "To-dos"
        case .coin: "Coin"
        case .rps: "RPS"
        case .custom: "Custom 1"
        case .custom2: "Custom 2"
        case .custom3: "Custom 3"
        }
    }

    /// Where a Custom list's options are saved (the first keeps the key from before there were three).
    var storageKey: String? {
        switch self {
        case .custom: "games.spinner.options"
        case .custom2: "games.spinner.options.2"
        case .custom3: "games.spinner.options.3"
        default: nil
        }
    }

    /// A preset's options, or nil for Custom and To-dos. Their IDs are fixed, so a saved pick still matches after a relaunch.
    var preset: [SpinnerOption]? { Self.presets[self] }

    private static let presets: [SpinnerList: [SpinnerOption]] = [
        .coin: fixed(["Heads", "Tails"], list: 1),
        .rps: fixed(["Rock", "Paper", "Scissors"], list: 2),
    ]

    private static func fixed(_ texts: [String], list: Int) -> [SpinnerOption] {
        texts.enumerated().map { index, text in
            SpinnerOption(id: UUID(uuidString: String(format: "5917E000-0000-0000-%04d-%012d", list, index))!, text: text)
        }
    }
}

/// The Spinner game: a list of options and a highlight that runs down it, slows down and stops on a random one.
/// The Custom lists are typed in and saved across launches; the others can't be edited.
@Observable
final class SpinnerStore {
    /// The list showing, saved so the page opens on it again.
    private(set) var list: SpinnerList
    /// Your own options, per Custom list.
    private var customs: [SpinnerList: [SpinnerOption]] = [:]
    /// The Custom list showing (empty on the others, which can't be edited).
    private var custom: [SpinnerOption] {
        get { customs[list] ?? [] }
        set { if list.isCustom { customs[list] = newValue } }
    }
    /// Each list's highlight: moving while spinning, then the pick once it stops. Kept per list and saved,
    /// so switching lists or relaunching never loses a pick.
    private var picks: [SpinnerList: SpinnerOption.ID] = [:]
    /// The option the highlight is on in the list showing.
    var highlightedID: SpinnerOption.ID? { picks[list] }
    private(set) var isSpinning = false
    /// Mixing up Custom's order, or just mixed up: its rows show their order (1, 2, 3…) until the next spin or
    /// an option is added or deleted.
    private(set) var isShuffling = false
    private(set) var isShuffled = false

    /// Your unchecked to-dos, oldest first, for the To-dos list (set by `AppController`; reading them through
    /// this keeps the page in step as you check things off).
    @ObservationIgnored var todoOptions: () -> [SpinnerOption] = { [] }

    static let maxOptions = 50
    static let maxLength = 40
    private static let listKey = "games.spinner.list"
    private static let picksKey = "games.spinner.picks"

    init() {
        list = UserDefaults.standard.string(forKey: Self.listKey).flatMap(SpinnerList.init) ?? .custom
        for list in SpinnerList.allCases {
            if let key = list.storageKey, let data = UserDefaults.standard.data(forKey: key),
               let saved = try? JSONDecoder().decode([SpinnerOption].self, from: data) {
                customs[list] = saved
            }
        }
        let saved = UserDefaults.standard.dictionary(forKey: Self.picksKey) as? [String: String] ?? [:]
        for (list, id) in saved {
            if let list = SpinnerList(rawValue: list), let id = UUID(uuidString: id) { picks[list] = id }
        }
    }

    /// The options of the list showing.
    var options: [SpinnerOption] {
        switch list {
        case .todos: todoOptions()
        case .coin, .rps: list.preset ?? []
        case .custom, .custom2, .custom3: custom
        }
    }

    var canSpin: Bool { !isSpinning && !isShuffling && options.count >= 2 }
    var canShuffle: Bool { list.isCustom && canSpin }

    /// The next (+1) or previous (-1) list, wrapping around.
    func stepList(by offset: Int) {
        guard !isSpinning, !isShuffling else { return }
        let all = SpinnerList.allCases
        let index = all.firstIndex(of: list)!
        list = all[((index + offset) % all.count + all.count) % all.count]
        isShuffled = false
        UserDefaults.standard.set(list.rawValue, forKey: Self.listKey)
    }

    /// Adds an option at the bottom of the Custom list showing as soon as something is typed on the blank row. Keeps the
    /// blank row's ID so the row being typed on stays the same view.
    func add(id: SpinnerOption.ID, text: String) {
        guard list.isCustom, custom.count < Self.maxOptions else { return }
        custom.append(SpinnerOption(id: id, text: String(text.prefix(Self.maxLength))))
        isShuffled = false
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
        if picks[list] == id { setPick(nil, in: list) }
        isShuffled = false
        save()
    }

    /// Picks the winner first, then runs the highlight down the list (a lap or more) to land on it,
    /// fast at first and slowing to a stop, about 2–3 seconds in all. A long list (many steps) runs faster,
    /// so it never takes longer than about 3 seconds.
    func spin() {
        guard canSpin else { return }
        let options = options
        let count = options.count
        let start = highlightedID.flatMap { id in options.firstIndex { $0.id == id } } ?? -1
        let winner = Int.random(in: 0..<count)
        var steps = ((winner - start) % count + count) % count
        while steps < 16 { steps += count }
        let pace = min(1, 24 / Double(steps)) // each step averages about 0.12s, so 24 steps is about 3s

        let list = list
        isSpinning = true
        isShuffled = false
        Task { @MainActor [weak self] in
            for step in 1...steps {
                let progress = Double(step) / Double(steps)
                try? await Task.sleep(for: .seconds(pace * (0.04 + 0.32 * pow(progress, 3))))
                guard let self else { return }
                picks[list] = options[(start + step) % count].id
            }
            self?.setPick(options[winner].id, in: list) // saves it
            self?.isSpinning = false
        }
    }

    /// Mixes up the Custom list's order a few times quickly (the rows slide around), then settles on a new order,
    /// which is saved. Always a different order from before.
    func shuffle() {
        guard canShuffle else { return }
        let before = custom.map(\.id)
        var final = custom
        while final.map(\.id) == before { final.shuffle() }
        isShuffling = true
        Task { @MainActor [weak self] in
            for _ in 0..<3 {
                guard let self else { return }
                custom.shuffle()
                try? await Task.sleep(for: .seconds(0.22))
            }
            guard let self else { return }
            custom = final
            isShuffling = false
            isShuffled = true
            save()
        }
    }

    private func setPick(_ id: SpinnerOption.ID?, in list: SpinnerList) {
        picks[list] = id
        let saved = Dictionary(uniqueKeysWithValues: picks.map { ($0.key.rawValue, $0.value.uuidString) })
        UserDefaults.standard.set(saved, forKey: Self.picksKey)
    }

    private func save() {
        if let key = list.storageKey, let data = try? JSONEncoder().encode(custom) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
