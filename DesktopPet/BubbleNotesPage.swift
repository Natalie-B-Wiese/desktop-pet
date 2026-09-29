import SwiftUI

/// The bubble's notes: write one at the top; click any note to edit it in place.
struct BubbleNotesPage: View {
    let store: NoteStore
    var onBack: () -> Void
    var onClose: () -> Void

    @State private var newText = ""
    @FocusState private var focused: Field?

    private enum Field: Hashable {
        case new
        case note(Note.ID)
    }

    /// Past this many notes the list scrolls instead of making the bubble taller.
    private static let maxVisibleNotes = 5
    private static let scrollHeight: CGFloat = 230

    var body: some View {
        VStack(spacing: 6) {
            Text("Notes")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .padding(.bottom, 2)

            TextField("Write a note", text: Binding(
                get: { newText },
                set: { newText = String($0.prefix(NoteStore.maxLength)) }
            ), axis: .vertical)
            .lineLimit(1...4)
            .bubbleFieldStyle()
            .focused($focused, equals: .new)
            .onSubmit {
                store.add(newText)
                newText = ""
                focused = .new // ready for another
            }
            .onExitCommand(perform: onClose) // Esc closes the menu

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
        .onChange(of: focused) { previous, _ in
            // Leaving a note that was edited down to nothing removes it.
            if case .note(let id) = previous { store.removeIfEmpty(id) }
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
        HStack(alignment: .top, spacing: 4) {
            TextField("Note", text: Binding(
                get: { store.notes.first { $0.id == note.id }?.text ?? "" },
                set: { store.update(note.id, text: $0) }
            ), axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .lineLimit(1...6)
            .focused($focused, equals: .note(note.id))
            .onSubmit { focused = nil } // Return finishes editing
            .onExitCommand { focused = nil }

            Button {
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
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.black.opacity(0.25), lineWidth: 1.5))
    }
}
