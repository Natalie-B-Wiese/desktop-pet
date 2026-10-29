import AppKit
import Observation

struct Todo: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String
    var createdAt = Date()
    /// When it was checked off, or nil while it's still to do.
    var completedAt: Date?

    var isDone: Bool { completedAt != nil }
}

/// The to-do list, saved across launches. Checked-off items move to the archive once their day is over,
/// and leave the archive after `archiveDays`.
@Observable
final class TodoStore {
    /// Every item in the order you put them in. Checking one off doesn't move it here,
    /// so unchecking puts it back where it was.
    private var items: [Todo] = []

    /// Unfinished items first, in your order (the ↑ ↓ arrows), then finished ones.
    var todos: [Todo] { items.filter { !$0.isDone } + items.filter(\.isDone) }

    var remainingCount: Int { items.filter { !$0.isDone }.count }

    /// Checked-off items from earlier days, most recently finished first.
    private(set) var archived: [Todo] = []

    /// How many days an item stays in the archive, counted from the day it was finished.
    var archiveDays: Int {
        didSet { UserDefaults.standard.set(archiveDays, forKey: Self.archiveDaysKey) }
    }
    static let archiveDayChoices = [1, 3, 7, 14, 30]
    static let defaultArchiveDays = 7

    /// Called whenever the list changes.
    @ObservationIgnored var onChange: (() -> Void)?
    /// Called when an item is checked off (not when it's unchecked), with whether that was the last one.
    @ObservationIgnored var onCheckedOff: ((_ allDone: Bool) -> Void)?
    @ObservationIgnored private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    static let maxLength = 60
    private static let storageKey = "todos"
    private static let archiveKey = "todos.archive"
    private static let archiveDaysKey = "todos.archiveDays"
    /// The day the archive was last pruned, so a relaunch the same day doesn't prune again.
    private static let archivePrunedKey = "todos.archivePruned"

    init() {
        archiveDays = UserDefaults.standard.object(forKey: Self.archiveDaysKey) as? Int ?? Self.defaultArchiveDays
        load()
        archiveFinishedFromEarlierDays()
        // The day can end while the app runs (midnight) or while the Mac sleeps.
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append((workspace, workspace.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.archiveFinishedFromEarlierDays() }))
        observers.append((NotificationCenter.default, NotificationCenter.default.addObserver(
            forName: .NSCalendarDayChanged, object: nil, queue: .main
        ) { [weak self] _ in self?.archiveFinishedFromEarlierDays() }))
    }

    deinit {
        for (center, observer) in observers { center.removeObserver(observer) }
    }

    func add(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        items.append(Todo(text: String(trimmed.prefix(Self.maxLength))))
        changed()
    }

    func toggle(_ id: Todo.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].completedAt = items[index].isDone ? nil : Date()
        let checkedOff = items[index].isDone
        changed()
        if checkedOff { onCheckedOff?(remainingCount == 0) }
    }

    func update(_ id: Todo.ID, text: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].text = String(text.prefix(Self.maxLength))
        changed()
    }

    /// Whether an unfinished item can move up (-1) or down (+1) past another unfinished one.
    /// Finished items stay at the bottom and don't move.
    func canMove(_ id: Todo.ID, by offset: Int) -> Bool {
        neighbor(of: id, by: offset) != nil
    }

    /// Swaps an unfinished item with the next unfinished one above (-1) or below (+1).
    func move(_ id: Todo.ID, by offset: Int) {
        guard let index = items.firstIndex(where: { $0.id == id }), let other = neighbor(of: id, by: offset) else { return }
        items.swapAt(index, other)
        changed()
    }

    /// The index of the nearest unfinished item above (-1) or below (+1) an unfinished one.
    private func neighbor(of id: Todo.ID, by offset: Int) -> Int? {
        guard let index = items.firstIndex(where: { $0.id == id }), !items[index].isDone else { return nil }
        let range = offset < 0 ? Array(items.indices.prefix(index).reversed()) : Array(items.indices.suffix(from: index + 1))
        return range.first { !items[$0].isDone }
    }

    /// Once an item is done being edited: trims it, or deletes it if it was emptied.
    func tidy(_ id: Todo.ID) {
        guard let todo = items.first(where: { $0.id == id }) else { return }
        let trimmed = todo.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            delete(id)
        } else if trimmed != todo.text {
            update(id, text: trimmed)
        }
    }

    func delete(_ id: Todo.ID) {
        items.removeAll { $0.id == id }
        changed()
    }

    /// Moves items checked off before today to the archive, and (once a day) deletes archived ones past `archiveDays`.
    func archiveFinishedFromEarlierDays() {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let finished = items.filter { ($0.completedAt ?? .distantFuture) < startOfToday }
        if !finished.isEmpty {
            items.removeAll { ($0.completedAt ?? .distantFuture) < startOfToday }
            archived = (archived + finished).sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
            changed()
        }
        pruneArchive()
    }

    /// How many were checked off on that day, on the list or in the archive (the greeting's "done yesterday").
    /// Ones restored or deleted since don't count.
    func finishedCount(on day: Date) -> Int {
        let calendar = Calendar.current
        return (items + archived).filter { $0.completedAt.map { calendar.isDate($0, inSameDayAs: day) } ?? false }.count
    }

    /// Puts an archived item back on the list, unchecked, at the bottom of the unchecked ones.
    func restore(_ id: Todo.ID) {
        guard let index = archived.firstIndex(where: { $0.id == id }) else { return }
        var todo = archived.remove(at: index)
        todo.completedAt = nil
        items.append(todo)
        changed()
    }

    func deleteArchived(_ id: Todo.ID) {
        archived.removeAll { $0.id == id }
        changed()
    }

    /// Deletes archived items finished more than `archiveDays` days before today (with 1 day, yesterday's stay
    /// today and are gone tomorrow). Only on the first check of each day (midnight, wake or launch), never right
    /// after `archiveDays` changes, so stepping through a short choice on the way never deletes anything.
    private func pruneArchive() {
        let calendar = Calendar.current
        let defaults = UserDefaults.standard
        if let last = defaults.object(forKey: Self.archivePrunedKey) as? Date, calendar.isDateInToday(last) { return }
        defaults.set(Date(), forKey: Self.archivePrunedKey)
        let today = calendar.startOfDay(for: Date())
        let before = archived.count
        archived.removeAll { todo in
            guard let done = todo.completedAt else { return true }
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: done), to: today).day ?? 0
            return days > archiveDays
        }
        if archived.count != before { changed() }
    }

    private func changed() {
        save()
        onChange?()
    }

    private func load() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Self.archiveKey), let saved = try? JSONDecoder().decode([Todo].self, from: data) {
            archived = saved
        }
        guard let data = defaults.data(forKey: Self.storageKey),
              let saved = try? JSONDecoder().decode([Todo].self, from: data) else { return }
        items = saved
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
        if let data = try? JSONEncoder().encode(archived) {
            UserDefaults.standard.set(data, forKey: Self.archiveKey)
        }
    }
}
