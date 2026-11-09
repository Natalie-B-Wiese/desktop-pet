import Foundation
import Observation

struct Note: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String
    var createdAt = Date()
    /// When its text last changed. Nil for notes not edited since this was added; they show `createdAt`.
    var editedAt: Date?

    /// The date shown under the note: when it was last edited, or written.
    var shownDate: Date { editedAt ?? createdAt }
}

/// Short notes, newest first, saved across launches.
@Observable
final class NoteStore {
    private(set) var notes: [Note] = []

    /// Only a safety cap, far past anything typed by hand; the Notes page says so if it's reached.
    static let maxLength = 10_000
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

    /// Whether a note already says exactly this (ignoring spaces around it).
    func contains(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return notes.contains { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed }
    }

    /// A copied text saved from the Clipboard's Text page, as a new note at the top.
    func addCopied(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= Self.maxLength, !contains(trimmed) else { return }
        add(id: UUID(), text: trimmed)
    }

    /// Saves edits as they're typed.
    func update(_ id: Note.ID, text: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        let limited = String(text.prefix(Self.maxLength))
        guard limited != notes[index].text else { return }
        notes[index].text = limited
        notes[index].editedAt = Date()
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

    /// Returns where it was, so Undo can put it back there.
    @discardableResult
    func delete(_ id: Note.ID) -> Int? {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return nil }
        notes.remove(at: index)
        save()
        return index
    }

    /// Undo: puts a deleted note back where it was.
    func undoDelete(_ note: Note, at index: Int) {
        guard !notes.contains(where: { $0.id == note.id }) else { return }
        notes.insert(note, at: min(index, notes.count))
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(notes) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
