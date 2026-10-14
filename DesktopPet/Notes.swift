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

    /// Adds a note at the top as soon as something is typed on the blank note. Keeps the
    /// blank note's ID so the note being typed on stays the same view.
    func add(id: Note.ID, text: String) {
        notes.insert(Note(id: id, text: String(text.prefix(Self.maxLength))), at: 0)
        save()
    }

    /// Saves edits as they're typed.
    func update(_ id: Note.ID, text: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].text = String(text.prefix(Self.maxLength))
        save()
    }

    /// Once a note is done being typed on: trims it, or deletes it if it was emptied.
    func tidy(_ id: Note.ID) {
        guard let note = notes.first(where: { $0.id == id }) else { return }
        let trimmed = note.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            delete(id)
        } else if trimmed != note.text {
            update(id, text: trimmed)
        }
    }

    func canMove(_ id: Note.ID, by offset: Int) -> Bool {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return false }
        return notes.indices.contains(index + offset)
    }

    /// Moves a note up (-1) or down (+1) in the list.
    func move(_ id: Note.ID, by offset: Int) {
        guard canMove(id, by: offset), let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes.swapAt(index, index + offset)
        save()
    }

    func delete(_ id: Note.ID) {
        notes.removeAll { $0.id == id }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(notes) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
