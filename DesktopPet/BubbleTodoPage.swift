import AppKit
import SwiftUI

/// The bubble's to-do list: add at the top, click a box to check an item off, click the text to edit it.
/// The Archived tab holds what was checked off on earlier days.
struct BubbleTodoPage: View {
    let store: TodoStore
    var onClose: () -> Void

    private enum Tab { case todos, archived }
    /// Always opens on To-dos; the archive is for now and then.
    @State private var tab = BubbleTodoPage.opensOnArchive ? Tab.archived : .todos
    /// For testing (`--archived`): opens on the Archived tab.
    static var opensOnArchive = false
    @State private var newText = ""
    @FocusState private var addFocused: Bool
    /// The to-do being edited in place, if any.
    @State private var editingID: Todo.ID?

    /// Past this many rows the list scrolls instead of making the bubble taller.
    private static let maxVisibleRows = 6
    fileprivate static let rowHeight: CGFloat = 30
    private static let rowSpacing: CGFloat = 4

    var body: some View {
        VStack(spacing: 6) {
            BubbleTabs(selection: $tab, options: [(.todos, "To-dos"), (.archived, "Archived")])
            if tab == .todos {
                todoList
            } else {
                ArchivedTodos(store: store)
            }
        }
        .onDisappear {
            if let id = editingID { store.tidy(id) }
        }
    }

    private var todoList: some View {
        VStack(spacing: 6) {
            TextField("Add a to-do", text: Binding(
                get: { newText },
                set: { newText = String($0.prefix(TodoStore.maxLength)) }
            ))
            .bubbleFieldStyle()
            .padding(.leading, 15) // lines up with the rows, past their reorder arrows
            .focused($addFocused)
            .onSubmit {
                store.add(newText)
                newText = ""
                addFocused = true // ready for the next one
            }
            .onExitCommand(perform: onClose) // Esc closes the menu

            if store.todos.isEmpty {
                Text("Nothing to do!")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .opacity(0.55)
                    .padding(.vertical, 4)
            } else if store.todos.count > Self.maxVisibleRows {
                ScrollView {
                    rows
                        .padding(1) // keeps the row outlines from being clipped at the edges
                }
                .scrollIndicators(.never) // a scroll bar would squeeze the rows narrower
                .frame(height: CGFloat(Self.maxVisibleRows) * (Self.rowHeight + Self.rowSpacing))
                .padding(.horizontal, -1)
            } else {
                rows
            }
        }
    }

    private var rows: some View {
        VStack(spacing: Self.rowSpacing) {
            ForEach(store.todos) { todo in
                HStack(spacing: 3) {
                    // Reorder arrows sit outside the row on the far left, like Notes'. Checked items stay at the bottom.
                    if todo.isDone {
                        Color.clear.frame(width: 12)
                    } else {
                        CaretStepper(
                            canIncrement: store.canMove(todo.id, by: -1),
                            canDecrement: store.canMove(todo.id, by: 1),
                            increment: { store.move(todo.id, by: -1) },
                            decrement: { store.move(todo.id, by: 1) },
                            repeatsWhenHeld: false, // one spot per click
                            outlined: false
                        )
                        .help("Move up or down")
                    }
                    TodoRow(
                        todo: todo,
                        isEditing: editingID == todo.id,
                        onEditingChanged: { editing in
                            if editing {
                                editingID = todo.id
                            } else if editingID == todo.id {
                                editingID = nil
                                store.tidy(todo.id) // trims it, or deletes it if emptied
                            }
                        },
                        onToggle: { store.toggle(todo.id) },
                        onType: { store.update(todo.id, text: $0) },
                        onDelete: { store.delete(todo.id) },
                        onClose: onClose
                    )
                }
            }
        }
    }
}

/// The Archived tab: to-dos checked off on earlier days under a heading for each day, newest first,
/// each with Restore and ✕, and how many days they're kept.
private struct ArchivedTodos: View {
    let store: TodoStore
    @State private var listHeight: CGFloat = 0

    /// Past this the list scrolls instead of making the bubble taller.
    private static let maxListHeight: CGFloat = 220

    var body: some View {
        VStack(spacing: 6) {
            // On top, so it stays in sight however long the list gets.
            keptForPicker
            if store.archived.isEmpty {
                Text("Nothing archived yet. Checked to-dos move here at the end of the day.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .opacity(0.55)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 4)
            } else {
                // Always a ScrollView, sized to its rows up to the cap, like Notes.
                ScrollView {
                    days
                        .padding(1) // keeps the row outlines from being clipped at the edges
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
                }
                .scrollIndicators(.never)
                .frame(height: min(listHeight, Self.maxListHeight))
                .padding(.horizontal, -1)
            }
        }
        // Waits for the arrows to settle, so a choice clicked past on the way doesn't delete anything.
        .task(id: store.archiveDays) {
            try? await Task.sleep(for: .milliseconds(600))
            if !Task.isCancelled { store.pruneArchive() }
        }
    }

    /// The archive split by the day each was finished, keeping its newest-first order.
    private var groups: [(day: Date, todos: [Todo])] {
        let calendar = Calendar.current
        var groups: [(day: Date, todos: [Todo])] = []
        for todo in store.archived {
            let day = calendar.startOfDay(for: todo.completedAt ?? Date())
            if groups.last?.day == day {
                groups[groups.count - 1].todos.append(todo)
            } else {
                groups.append((day, [todo]))
            }
        }
        return groups
    }

    private var days: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(groups, id: \.day) { group in
                Text(Self.dayText(group.day))
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .opacity(0.55)
                    .padding(.top, group.day == groups.first?.day ? 0 : 4)
                ForEach(group.todos) { row($0) }
            }
        }
    }

    /// "Yesterday", or "Mon, Oct 26".
    private static func dayText(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    private func row(_ todo: Todo) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.square.fill")
                .font(.system(size: 14, weight: .semibold))
                .opacity(0.45)
                .frame(width: 18, height: 18)
            Text(todo.text)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .opacity(0.65)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
            Button {
                store.restore(todo.id)
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 10, weight: .bold))
                    .opacity(0.6)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Put back on the list")
            Button {
                store.deleteArchived(todo.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .heavy))
                    .opacity(0.5)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Delete")
        }
        .padding(.leading, 8)
        .padding(.trailing, 3)
        .frame(minHeight: BubbleTodoPage.rowHeight)
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.black.opacity(0.25), lineWidth: 1.5))
    }

    /// "Kept for  ‹ 7 days ›", like the ‹ › rows in Settings. It doesn't wrap around,
    /// so one click from 1 day can't jump to 30, or from 30 to 1.
    private var keptForPicker: some View {
        let choices = TodoStore.archiveDayChoices
        let days = store.archiveDays
        return HStack(spacing: 0) {
            Text("Kept for")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: 0)
            HeaderIconButton(systemImage: "chevron.left", help: "Fewer days", width: 18) {
                if let fewer = choices.last(where: { $0 < days }) { store.archiveDays = fewer }
            }
            .disabled(choices.first.map { days <= $0 } ?? true)
            Text("\(days) day\(days == 1 ? "" : "s")")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .fixedSize()
                .frame(width: 58)
            HeaderIconButton(systemImage: "chevron.right", help: "More days", width: 18) {
                if let more = choices.first(where: { $0 > days }) { store.archiveDays = more }
            }
            .disabled(choices.last.map { days >= $0 } ?? true)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.black.opacity(0.25), lineWidth: 1.5))
        .help("How long checked to-dos stay here before they're deleted")
    }
}

/// One to-do: the box checks it off, and clicking the text edits it in place.
private struct TodoRow: View {
    let todo: Todo
    let isEditing: Bool
    var onEditingChanged: (Bool) -> Void
    var onToggle: () -> Void
    var onType: (String) -> Void
    var onDelete: () -> Void
    var onClose: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onToggle) {
                Image(systemName: todo.isDone ? "checkmark.square.fill" : "square")
                    .font(.system(size: 14, weight: .semibold))
                    .opacity(todo.isDone ? 0.45 : 1)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(todo.isDone ? "Mark as not done" : "Check off")

            TodoTextView(
                text: todo.text,
                isDone: todo.isDone,
                onType: onType,
                onEditingChanged: onEditingChanged,
                onClose: onClose
            )
            .padding(.vertical, 6)

            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .heavy))
                    .opacity(0.5)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Delete")
        }
        .padding(.leading, 8)
        .padding(.trailing, 3)
        .frame(minHeight: BubbleTodoPage.rowHeight)
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(
            isEditing ? Color.black : Color.black.opacity(0.25),
            lineWidth: isEditing ? 2 : 1.5
        ))
    }
}

/// A to-do's text, shown and edited in the same view so it wraps the same way either way.
///
/// Long names like `aspire_opportunity_services` would otherwise break wherever the line runs
/// out, so a zero-width space is drawn after each underscore and slash to let the line break
/// there. Those spaces are never saved, and the cursor and Backspace step over them.
private struct TodoTextView: NSViewRepresentable {
    let text: String
    let isDone: Bool
    var onType: (String) -> Void
    var onEditingChanged: (Bool) -> Void
    var onClose: () -> Void

    static let breakMark = "\u{200B}"
    private static let font: NSFont = {
        let base = NSFont.systemFont(ofSize: 12, weight: .medium)
        return base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: 12) } ?? base
    }()

    /// The saved text as it's drawn, with a break point after each underscore and slash.
    static func shown(_ text: String) -> String {
        text.replacingOccurrences(of: "_", with: "_" + breakMark)
            .replacingOccurrences(of: "/", with: "/" + breakMark)
    }

    /// What's typed, as it's saved: no break points or line breaks, at most `TodoStore.maxLength` long.
    static func saved(_ shown: String) -> String {
        let plain = shown.replacingOccurrences(of: breakMark, with: "")
            .replacingOccurrences(of: "\n", with: " ")
        return String(plain.prefix(TodoStore.maxLength))
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> TodoNSTextView {
        // TextKit 1, so the layout manager can measure the wrapped height.
        let view = TodoNSTextView(usingTextLayoutManager: false)
        view.delegate = context.coordinator
        view.drawsBackground = false
        view.isRichText = false
        view.allowsUndo = false // the text is rebuilt with break points as you type
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.textContainer?.widthTracksTextView = true
        view.isHorizontallyResizable = false
        view.isVerticallyResizable = false
        view.onFocusChange = { context.coordinator.parent.onEditingChanged($0) }
        apply(to: view)
        return view
    }

    func updateNSView(_ view: TodoNSTextView, context: Context) {
        context.coordinator.parent = self
        apply(to: view)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView view: TodoNSTextView, context: Context) -> CGSize? {
        guard let container = view.textContainer, let layout = view.layoutManager else { return nil }
        let width = proposal.width ?? 150
        container.size = NSSize(width: width, height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        let height = max(layout.usedRect(for: container).height, layout.defaultLineHeight(for: Self.font))
        return CGSize(width: width, height: height.rounded(.up))
    }

    private func apply(to view: TodoNSTextView) {
        let shown = Self.shown(text)
        if view.string != shown { view.string = shown }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: Self.font,
            .foregroundColor: NSColor.black.withAlphaComponent(isDone ? 0.45 : 1),
            .strikethroughStyle: isDone ? NSUnderlineStyle.single.rawValue : 0,
        ]
        view.typingAttributes = attributes
        view.textStorage?.setAttributes(attributes, range: NSRange(location: 0, length: view.textStorage?.length ?? 0))
        view.insertionPointColor = .black
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: TodoTextView

        init(_ parent: TodoTextView) { self.parent = parent }

        private func isBreakMark(_ view: NSTextView, at index: Int) -> Bool {
            let string = view.string as NSString
            return index >= 0 && index < string.length && string.substring(with: NSRange(location: index, length: 1)) == TodoTextView.breakMark
        }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            let saved = TodoTextView.saved(view.string)
            let shown = TodoTextView.shown(saved)
            if view.string != shown {
                // Rebuild the break points, keeping the cursor after the same typed character.
                let before = (view.string as NSString).substring(to: min(view.selectedRange().location, (view.string as NSString).length))
                let typedBefore = min(TodoTextView.saved(before).count, saved.count)
                let cursor = (TodoTextView.shown(String(saved.prefix(typedBefore))) as NSString).length
                view.string = shown
                view.setSelectedRange(NSRange(location: cursor, length: 0))
            }
            if saved != parent.text { parent.onType(saved) }
        }

        /// Never leaves the cursor between an underscore and its break point, so arrow keys
        /// don't need an extra press there.
        func textView(_ view: NSTextView, willChangeSelectionFromCharacterRange old: NSRange,
                      toCharacterRange new: NSRange) -> NSRange {
            guard new.length == 0, isBreakMark(view, at: new.location) else { return new }
            let movingLeft = new.location < old.location
            return NSRange(location: movingLeft ? new.location - 1 : new.location + 1, length: 0)
        }

        func textView(_ view: NSTextView, shouldChangeTextIn range: NSRange, replacementString text: String?) -> Bool {
            // Backspace right after an underscore would only delete its invisible break point;
            // delete the underscore too.
            if text?.isEmpty == true, range.length == 1, isBreakMark(view, at: range.location), range.location > 0 {
                let wider = NSRange(location: range.location - 1, length: 2)
                if view.shouldChangeText(in: wider, replacementString: "") {
                    view.textStorage?.replaceCharacters(in: wider, with: "")
                    view.didChangeText()
                }
                return false
            }
            return true
        }

        func textView(_ view: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.insertNewline(_:)):
                view.window?.makeFirstResponder(nil) // Return finishes editing
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onClose() // Esc closes the menu
                return true
            default:
                return false
            }
        }
    }
}

private final class TodoNSTextView: NSTextView {
    var onFocusChange: ((Bool) -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became { onFocusChange?(true) }
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { onFocusChange?(false) }
        return resigned
    }

    /// Copies the text without its invisible break points.
    override func writeSelection(to pboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
        let selected = (string as NSString).substring(with: selectedRange())
        pboard.clearContents()
        return pboard.setString(selected.replacingOccurrences(of: TodoTextView.breakMark, with: ""), forType: .string)
    }
}
