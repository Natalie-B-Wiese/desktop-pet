import SwiftUI

/// The bubble's "Reminders" page: every upcoming reminder (click one to edit it), and Add.
struct BubbleRemindersPage: View {
    let store: ReminderStore
    var onAdd: () -> Void
    var onEdit: (Reminder.ID) -> Void

    /// Past this many rows the list scrolls instead of making the bubble taller.
    private static let maxVisibleRows = 4
    private static let rowHeight: CGFloat = 38
    private static let rowSpacing: CGFloat = 6

    var body: some View {
        let upcoming = store.upcoming
        VStack(spacing: 6) {

            if upcoming.isEmpty {
                Text("No reminders yet")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .opacity(0.55)
                    .padding(.vertical, 4)
            } else if upcoming.count > Self.maxVisibleRows {
                ScrollView {
                    rows(upcoming)
                        .padding(1) // keeps the row outlines from being clipped at the edges
                }
                .scrollIndicators(.never) // a scroll bar would squeeze the rows narrower
                .frame(height: CGFloat(Self.maxVisibleRows) * (Self.rowHeight + Self.rowSpacing))
                .padding(.horizontal, -1)
            } else {
                rows(upcoming)
            }

            BubbleButton("Add reminder", systemImage: "plus", action: onAdd)
        }
    }

    private func rows(_ reminders: [Reminder]) -> some View {
        VStack(spacing: Self.rowSpacing) {
            ForEach(reminders) { reminder in
                row(reminder)
            }
        }
    }

    private func row(_ reminder: Reminder) -> some View {
        HStack(spacing: 6) {
            Button {
                onEdit(reminder.id)
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    Text(ReminderStore.timeText(reminder.date))
                        .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                    if let text = reminder.message {
                        Text(text)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .opacity(0.65)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Edit reminder")

            Button {
                store.delete(reminder.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .heavy))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Delete reminder")
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .padding(.vertical, 5)
        .frame(minHeight: Self.rowHeight)
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.black.opacity(0.25), lineWidth: 1.5))
    }
}

/// The bubble's "Remind me at…" page, also used to edit an existing reminder.
struct BubbleAddReminderPage: View {
    let store: ReminderStore
    /// The reminder being changed, or nil when adding a new one.
    var editing: Reminder? = nil
    var onAdded: () -> Void
    var onClose: () -> Void

    @State private var time: Date
    @State private var message: String
    @FocusState private var timeFocused: Bool

    init(store: ReminderStore, editing: Reminder? = nil, onAdded: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.store = store
        self.editing = editing
        self.onAdded = onAdded
        self.onClose = onClose
        _time = State(initialValue: editing?.date ?? ReminderStore.defaultTime())
        _message = State(initialValue: editing?.message ?? "")
    }

    var body: some View {
        VStack(spacing: 8) {

            VStack(spacing: 2) {
                DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .datePickerStyle(.field)
                    .controlSize(.large)
                    .focused($timeFocused)
                Text(ReminderStore.dayWord(for: time))
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .opacity(0.55)
            }

            TextField("Message (optional)", text: Binding(
                get: { message },
                set: { message = String($0.prefix(ReminderStore.maxMessageLength)) }
            ))
            .bubbleFieldStyle()
            .onSubmit(save) // Return adds or saves it

            if editing == nil {
                BubbleButton("Add", systemImage: "bell.badge", action: save)
            } else {
                BubbleButton("Save", systemImage: "checkmark", action: save)
            }
        }
        .onAppear {
            // Wait a moment for the bubble to become the key window before focusing.
            DispatchQueue.main.async { timeFocused = true }
        }
        .onExitCommand(perform: onClose) // Esc closes the menu
    }

    private func save() {
        let text = ReminderStore.cleanMessage(message)
        if let editing {
            store.update(editing.id, at: time, message: text)
        } else {
            store.add(at: time, message: text)
        }
        onAdded()
    }
}

/// What the bubble shows when a reminder comes due.
struct BubbleReminderAlert: View {
    let reminder: Reminder
    /// How many more are waiting after this one.
    let moreCount: Int

    var body: some View {
        VStack(spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: "bell.fill")
                    .font(.system(size: 9, weight: .bold))
                Text(reminder.date.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
            }
            Text(reminder.message ?? "Reminder!")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 180)
                .fixedSize(horizontal: false, vertical: true)
            Text(moreCount > 0 ? "Click to close · \(moreCount) more" : "Click to close")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .opacity(0.55)
        }
    }
}
