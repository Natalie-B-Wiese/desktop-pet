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

/// The to-do list, saved across launches. Checked-off items are cleared once their day is over.
@Observable
final class TodoStore {
    /// Every item in the order you put them in. Checking one off doesn't move it here,
    /// so unchecking puts it back where it was.
    private var items: [Todo] = []

    /// Unfinished items first, in your order (the ↑ ↓ arrows), then finished ones.
    var todos: [Todo] { items.filter { !$0.isDone } + items.filter(\.isDone) }

    var remainingCount: Int { items.filter { !$0.isDone }.count }

    /// Called whenever the list changes.
    @ObservationIgnored var onChange: (() -> Void)?
    /// Called when an item is checked off (not when it's unchecked), with whether that was the last one.
    @ObservationIgnored var onCheckedOff: ((_ allDone: Bool) -> Void)?
    @ObservationIgnored private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    static let maxLength = 60
    private static let storageKey = "todos"

    init() {
        load()
        clearFinishedFromEarlierDays()
        // The day can end while the app runs (midnight) or while the Mac sleeps.
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append((workspace, workspace.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.clearFinishedFromEarlierDays() }))
        observers.append((NotificationCenter.default, NotificationCenter.default.addObserver(
            forName: .NSCalendarDayChanged, object: nil, queue: .main
        ) { [weak self] _ in self?.clearFinishedFromEarlierDays() }))
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

    /// Deletes items that were checked off before today.
    func clearFinishedFromEarlierDays() {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let before = items.count
        items.removeAll { ($0.completedAt ?? .distantFuture) < startOfToday }
        if items.count != before { changed() }
    }

    private func changed() {
        save()
        onChange?()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let saved = try? JSONDecoder().decode([Todo].self, from: data) else { return }
        items = saved
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
