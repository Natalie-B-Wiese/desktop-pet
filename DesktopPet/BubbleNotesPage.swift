import SwiftUI

/// The bubble's notes. A box at the top grows as you type; Return saves the note and ⇧Return
/// (or ⌥Return) starts a new line. Clicking a note loads it into the same box, where edits save
/// as you type; Return, Esc or clicking away finishes.
struct BubbleNotesPage: View {
    let store: NoteStore
    var onClose: () -> Void

    @State private var draft = ""
    /// The note being edited in the box, or nil when writing a new one.
    @State private var editingID: Note.ID?
    @FocusState private var editorFocused: Bool

    /// Past this many notes the list scrolls instead of making the bubble taller.
    private static let maxVisibleNotes = 5
    private static let scrollHeight: CGFloat = 230
    /// The box grows up to this many lines, then scrolls.
    private static let maxEditorLines = 6

    private var isDraftEmpty: Bool {
        draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 6) {

            editor

            if store.notes.isEmpty {
                Text("Jot something down so you don't forget.\nReturn saves, ⇧Return adds a line.")
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

        }
        .onDisappear(perform: finish) // closing the page keeps a half-written note
    }

    private var editor: some View {
        TextField(editingID == nil ? "Write a note" : "Edit note", text: Binding(
            get: { draft },
            set: { text in
                draft = String(text.prefix(NoteStore.maxLength))
                if let id = editingID, !isDraftEmpty { store.update(id, text: draft) }
            }
        ), axis: .vertical)
        .lineLimit(1...Self.maxEditorLines)
        .bubbleFieldStyle()
        .focused($editorFocused)
        .onSubmit {
            // ⇧Return adds a line where the cursor is (⌥Return already does); Return saves.
            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                NSApp.sendAction(#selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)), to: nil, from: nil)
            } else {
                finish()
            }
            editorFocused = true
        }
        .onChange(of: editorFocused) { _, focused in
            if !focused && editingID != nil { finish() } // clicking away finishes an edit
        }
        .onExitCommand { // Esc: stop editing, or close the menu if not editing
            if editingID != nil { finish() } else { onClose() }
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
                if isEditing { editingID = nil; draft = "" }
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
        finish()
        editingID = note.id
        draft = note.text
        editorFocused = true
    }

    /// Adds the draft as a new note, or finishes editing one (removing it if it was emptied).
    private func finish() {
        if let id = editingID {
            if isDraftEmpty {
                store.delete(id)
            } else {
                store.update(id, text: draft.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            editingID = nil
        } else {
            store.add(draft) // ignores an empty draft
        }
        draft = ""
    }
}
