import SwiftUI

/// The bubble's notes, typed on directly. A blank note sits at the top; typing on it makes it a
/// real note and a new blank one appears above it. Clicking a note edits it in place. Everything
/// saves as it's typed, and Return adds a line.
struct BubbleNotesPage: View {
    let store: NoteStore
    var onClose: () -> Void

    /// The blank note's ID. It becomes the new note's ID once something is typed on it.
    @State private var blankID = UUID()
    @FocusState private var focusedID: Note.ID?
    @State private var listHeight: CGFloat = 0

    /// Past this height the list scrolls instead of making the bubble taller.
    private static let maxListHeight: CGFloat = 260

    var body: some View {
        // Always a ScrollView (even when short) so the note being typed on is never rebuilt
        // and never loses the keyboard when the list starts scrolling.
        ScrollView {
            VStack(spacing: 4) {
                ForEach([Note(id: blankID, text: "")] + store.notes) { note in
                    row(note)
                }
            }
            .padding(1) // keeps the outlines from being clipped at the edges
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
        }
        .scrollIndicators(.never)
        .frame(height: min(listHeight, Self.maxListHeight))
        .padding(.horizontal, -1)
        .onChange(of: focusedID) { old, _ in
            if let old { store.tidy(old) }
        }
        .onDisappear {
            if let id = focusedID { store.tidy(id) }
        }
    }

    private func row(_ note: Note) -> some View {
        HStack(spacing: 3) {
            // Reorder arrows sit outside the note on the far left, like the clipboard's.
            if note.id == blankID {
                Color.clear.frame(width: 12) // the blank note always stays on top
            } else {
                CaretStepper(
                    canIncrement: store.canMove(note.id, by: -1),
                    canDecrement: store.canMove(note.id, by: 1),
                    increment: { store.move(note.id, by: -1) },
                    decrement: { store.move(note.id, by: 1) },
                    repeatsWhenHeld: false, // one spot per click
                    outlined: false
                )
                .help("Move up or down")
            }

            NoteRow(
                note: note,
                isBlank: note.id == blankID,
                focusedID: $focusedID,
                onType: { type($0, on: note.id) },
                onDelete: { store.delete(note.id) },
                onClose: onClose
            )
        }
    }

    private func type(_ text: String, on id: Note.ID) {
        if id == blankID {
            guard !text.isEmpty else { return }
            store.add(id: id, text: text)
            blankID = UUID() // a fresh blank note appears above; typing carries on here
        } else {
            store.update(id, text: text)
        }
    }
}

/// One note, typed on in place.
private struct NoteRow: View {
    let note: Note
    let isBlank: Bool
    var focusedID: FocusState<Note.ID?>.Binding
    var onType: (String) -> Void
    var onDelete: () -> Void
    var onClose: () -> Void

    /// The editor's own copy of the text. Feeding the editor straight from the store makes
    /// macOS move the cursor to the end after every keystroke.
    @State private var text: String

    private static let font = Font.system(size: 12, weight: .medium, design: .rounded)
    /// TextEditor's own inset before the text starts, matched by the sizing text.
    private static let editorInset: CGFloat = 5

    init(note: Note, isBlank: Bool, focusedID: FocusState<Note.ID?>.Binding,
         onType: @escaping (String) -> Void, onDelete: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.note = note
        self.isBlank = isBlank
        self.focusedID = focusedID
        self.onType = onType
        self.onDelete = onDelete
        self.onClose = onClose
        _text = State(initialValue: note.text)
    }

    var body: some View {
        let isFocused = focusedID.wrappedValue == note.id
        HStack(alignment: .top, spacing: 4) {
            editor

            if isBlank {
                Color.clear.frame(width: 18, height: 18) // lines up with the ✕ on real notes
            } else {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .heavy))
                        .opacity(0.5)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Delete note")
            }
        }
        .padding(.leading, 3)
        .padding(.trailing, 3)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color(red: 1, green: 0.97, blue: 0.8)) // sticky-note yellow
                .onTapGesture { focusedID.wrappedValue = note.id } // clicking the note's margin types on it too
        )
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(
            isFocused ? Color.black : Color.black.opacity(0.25),
            lineWidth: isFocused ? 2 : 1.5
        ))
        .onChange(of: text) { _, newText in
            let limited = String(newText.prefix(NoteStore.maxLength))
            if limited != newText { text = limited; return }
            if limited != note.text { onType(limited) }
        }
        .onChange(of: note.text) { _, saved in
            if saved != text { text = saved } // e.g. trimmed after typing stopped
        }
    }

    /// A TextEditor exactly as tall as its text: an invisible copy of the text sets the height.
    private var editor: some View {
        Text(sizingText)
            .font(Self.font)
            .padding(.horizontal, Self.editorInset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .hidden()
            .overlay {
                TextEditor(text: $text)
                    .font(Self.font)
                    .scrollContentBackground(.hidden)
                    .scrollDisabled(true)
                    .focused(focusedID, equals: note.id)
                    .onExitCommand(perform: onClose) // Esc closes the menu
            }
            .overlay(alignment: .topLeading) {
                if isBlank && text.isEmpty {
                    Text("New note")
                        .font(Self.font)
                        .opacity(0.35)
                        .padding(.leading, Self.editorInset)
                        .allowsHitTesting(false)
                }
            }
    }

    /// The text that sizes the editor. A trailing empty line (or no text at all) still takes a line.
    private var sizingText: String {
        text.isEmpty || text.hasSuffix("\n") ? text + " " : text
    }
}
