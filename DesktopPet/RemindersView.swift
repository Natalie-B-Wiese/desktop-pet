import SwiftUI

/// The Reminders window: every reminder, with delete buttons and a form to add more.
struct RemindersView: View {
    let store: ReminderStore

    @State private var time = ReminderStore.defaultTime()
    @State private var message = ""

    var body: some View {
        VStack(spacing: 0) {
            if store.reminders.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "bell.slash")
                        .font(.system(size: 28))
                        .foregroundStyle(.tertiary)
                    Text("No reminders yet")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(store.reminders) { reminder in
                        row(reminder)
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("New reminder")
                    .font(.headline)
                HStack(spacing: 8) {
                    DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                    Text(ReminderStore.dayWord(for: time))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 60, alignment: .leading)
                    TextField("Message (optional)", text: Binding(
                        get: { message },
                        set: { message = String($0.prefix(ReminderStore.maxMessageLength)) }
                    ))
                    .onSubmit(add)
                    Button("Add", action: add)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(16)
        }
        .frame(width: 440, height: 360)
    }

    private func row(_ reminder: Reminder) -> some View {
        let isDue = store.due.contains(reminder)
        return HStack(spacing: 10) {
            Image(systemName: isDue ? "bell.badge.fill" : "bell")
                .foregroundStyle(isDue ? Color.orange : .secondary)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(ReminderStore.timeText(reminder.date))
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                if let text = reminder.message {
                    Text(text)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if isDue {
                Text("Due")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }
            Button {
                store.delete(reminder.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Delete reminder")
        }
        .padding(.vertical, 3)
    }

    private func add() {
        store.add(at: time, message: ReminderStore.cleanMessage(message))
        message = ""
        time = ReminderStore.defaultTime()
    }
}
