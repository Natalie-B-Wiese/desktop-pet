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
    /// Unfinished items first (oldest first), then finished ones.
    private(set) var todos: [Todo] = []

    var remainingCount: Int { todos.filter { !$0.isDone }.count }

    /// Called whenever the list changes.
    @ObservationIgnored var onChange: (() -> Void)?
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
        todos.append(Todo(text: String(trimmed.prefix(Self.maxLength))))
        changed()
    }

    func toggle(_ id: Todo.ID) {
        guard let index = todos.firstIndex(where: { $0.id == id }) else { return }
        todos[index].completedAt = todos[index].isDone ? nil : Date()
        changed()
    }

    func update(_ id: Todo.ID, text: String) {
        guard let index = todos.firstIndex(where: { $0.id == id }) else { return }
        todos[index].text = String(text.prefix(Self.maxLength))
        changed()
    }

    /// Once an item is done being edited: trims it, or deletes it if it was emptied.
    func tidy(_ id: Todo.ID) {
        guard let todo = todos.first(where: { $0.id == id }) else { return }
        let trimmed = todo.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            delete(id)
        } else if trimmed != todo.text {
            update(id, text: trimmed)
        }
    }

    func delete(_ id: Todo.ID) {
        todos.removeAll { $0.id == id }
        changed()
    }

    /// Deletes items that were checked off before today.
    func clearFinishedFromEarlierDays() {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        let before = todos.count
        todos.removeAll { ($0.completedAt ?? .distantFuture) < startOfToday }
        if todos.count != before { changed() }
    }

    private func changed() {
        todos.sort { a, b in
            if a.isDone != b.isDone { return !a.isDone }
            return a.createdAt < b.createdAt
        }
        save()
        onChange?()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let saved = try? JSONDecoder().decode([Todo].self, from: data) else { return }
        todos = saved
    }

    private func save() {
        if let data = try? JSONEncoder().encode(todos) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
