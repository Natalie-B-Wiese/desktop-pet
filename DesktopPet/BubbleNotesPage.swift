import SwiftUI

/// The bubble's notes. A multi-line box at the top writes new notes; clicking a note loads it
/// into the same box to edit. Return adds a line; the button (or ⌘Return) adds or saves.
struct BubbleNotesPage: View {
    let store: NoteStore
    var onBack: () -> Void
    var onClose: () -> Void

    @State private var draft = ""
    /// The note being edited in the box, or nil when writing a new one.
    @State private var editingID: Note.ID?
    @FocusState private var editorFocused: Bool

    /// Past this many notes the list scrolls instead of making the bubble taller.
    private static let maxVisibleNotes = 5
    private static let scrollHeight: CGFloat = 230
    private static let editorHeight: CGFloat = 72 // about 4 lines

    private var isDraftEmpty: Bool {
        draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 6) {
            Text("Notes")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .padding(.bottom, 2)

            editor

            if editingID == nil {
                BubbleButton("Add note", systemImage: "plus", centered: true, action: submit)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(isDraftEmpty)
                    .opacity(isDraftEmpty ? 0.4 : 1)
            } else {
                HStack(spacing: 6) {
                    BubbleButton("Cancel", style: .quiet, centered: true, action: stopEditing)
                    BubbleButton("Save", systemImage: "checkmark", centered: true, action: submit)
                        .keyboardShortcut(.return, modifiers: .command)
                }
            }

            if store.notes.isEmpty {
                Text("Jot something down so you don't forget.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .multilineTextAlignment(.center)
                    .opacity(0.55)
                    .padding(.vertical, 4)
            } else if store.notes.count > Self.maxVisibleNotes {
                ScrollView {
                    rows.padding(1) // keeps the outlines from being clipped at the edges
                }
                .scrollIndicators(.never)
                .frame(height: Self.scrollHeight)
                .padding(.horizontal, -1)
            } else {
                rows
            }

            BubbleButton("Back", systemImage: "chevron.left", style: .quiet, action: onBack)
        }
    }

    private var editor: some View {
        TextEditor(text: Binding(
            get: { draft },
            set: { draft = String($0.prefix(NoteStore.maxLength)) }
        ))
        .font(.system(size: 12, weight: .medium, design: .rounded))
        .scrollContentBackground(.hidden)
        .focused($editorFocused)
        .padding(.horizontal, 3)
        .padding(.vertical, 4)
        .frame(height: Self.editorHeight)
        .background(RoundedRectangle(cornerRadius: 7).fill(.white))
        .overlay(alignment: .topLeading) {
            // Placeholder where typing starts (TextEditor has none of its own).
            if draft.isEmpty {
                Text("Write a note")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .opacity(0.35)
                    .padding(.leading, 8)
                    .padding(.top, 4)
                    .allowsHitTesting(false)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(.black, lineWidth: 1.5))
        .onExitCommand { // Esc: stop editing, or close the menu if not editing
            if editingID != nil { stopEditing() } else { onClose() }
        }
    }

    private var rows: some View {
        VStack(spacing: 4) {
            ForEach(store.notes) { note in
                row(note)
            }
        }
    }

    private func row(_ note: Note) -> some View {
        let isEditing = editingID == note.id
        return HStack(alignment: .top, spacing: 4) {
            Button {
                startEditing(note)
            } label: {
                Text(note.text)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .lineLimit(6)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Edit note")

            Button {
                if isEditing { stopEditing() }
                store.delete(note.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .heavy))
                    .opacity(0.5)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Delete note")
        }
        .padding(.leading, 8)
        .padding(.trailing, 3)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color(red: 1, green: 0.97, blue: 0.8))) // sticky-note yellow
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(
            isEditing ? Color.black : Color.black.opacity(0.25),
            lineWidth: isEditing ? 2 : 1.5
        ))
    }

    private func startEditing(_ note: Note) {
        editingID = note.id
        draft = note.text
        editorFocused = true
    }

    private func stopEditing() {
        editingID = nil
        draft = ""
    }

    /// Adds a new note, or saves the one being edited (removing it if it was emptied).
    private func submit() {
        if let id = editingID {
            if isDraftEmpty {
                store.delete(id)
            } else {
                store.update(id, text: draft.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            stopEditing()
        } else {
            guard !isDraftEmpty else { return }
            store.add(draft)
            draft = ""
        }
        editorFocused = true
    }
}
