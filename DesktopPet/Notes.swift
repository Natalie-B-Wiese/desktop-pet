import Foundation
import Observation

struct Note: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String
    var createdAt = Date()
}

/// Short notes, newest first, saved across launches.
@Observable
final class NoteStore {
    private(set) var notes: [Note] = []

    static let maxLength = 200
    private static let storageKey = "notes"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode([Note].self, from: data) {
            notes = saved
        }
    }

    func add(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        notes.insert(Note(text: String(trimmed.prefix(Self.maxLength))), at: 0)
        save()
    }

    /// Saves edits as they're typed.
    func update(_ id: Note.ID, text: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].text = String(text.prefix(Self.maxLength))
        save()
    }

    func delete(_ id: Note.ID) {
        notes.removeAll { $0.id == id }
        save()
    }

    /// A note edited down to nothing is removed once you're done with it.
    func removeIfEmpty(_ id: Note.ID) {
        guard let note = notes.first(where: { $0.id == id }),
              note.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        delete(id)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(notes) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
