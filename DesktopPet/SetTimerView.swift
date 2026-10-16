import SwiftUI

/// The minutes last picked, shared by the bubble's timer page and the Set Timer window.
enum TimerDraft {
    static let minutesKey = "customTimer.minutes"
    static let defaultMinutes = 20

    static let pomodoroWorkKey = "pomodoro.workMinutes"
    static let pomodoroBreakKey = "pomodoro.breakMinutes"
    static let defaultWorkMinutes = 25
    static let defaultBreakMinutes = 5
    static let pomodoroRange = 1...180

    /// The bubble's Timer page splits the minutes into hours and minutes (up to 99:59).
    static let maxHours = 99
    static let minuteRange = 0...(maxHours * 60 + 59)

    static let maxLabelLength = 30

    /// Trims a typed label; an empty one means "no label".
    static func cleanLabel(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// A text binding that stops accepting characters past `maxLabelLength`.
    static func limited(_ text: Binding<String>) -> Binding<String> {
        Binding(
            get: { text.wrappedValue },
            set: { text.wrappedValue = String($0.prefix(maxLabelLength)) }
        )
    }

    /// The quick-adjust buttons, in minutes.
    static let steps = [-10, -5, 5, 10]

    static func stepTitle(_ step: Int) -> String {
        step > 0 ? "+\(step)" : "−\(-step)"
    }

    /// Adds `step` minutes, never going below zero.
    static func adjust(_ minutes: inout Int, by step: Int) {
        minutes = min(max(minutes + step, minuteRange.lowerBound), minuteRange.upperBound)
    }

    /// A text binding that only keeps digits and stays within `range`.
    /// It updates on every keystroke, so pressing Start right after typing uses what was typed.
    static func digits(_ value: Binding<Int>, in range: ClosedRange<Int>) -> Binding<String> {
        Binding(
            get: { String(value.wrappedValue) },
            set: { text in
                let number = Int(text.filter(\.isNumber).prefix(3)) ?? 0
                value.wrappedValue = min(max(number, range.lowerBound), range.upperBound)
            }
        )
    }
}

/// The "Custom…" timer window: pick a number of minutes, then Start.
struct SetTimerView: View {
    var onStart: (_ duration: TimeInterval, _ label: String?) -> Void
    var onCancel: () -> Void

    @AppStorage(TimerDraft.minutesKey) private var minutes = TimerDraft.defaultMinutes
    @State private var label = ""

    private var duration: TimeInterval { TimeInterval(minutes * 60) }

    var body: some View {
        VStack(spacing: 16) {
            field("Minutes", value: $minutes, range: TimerDraft.minuteRange)

            HStack(spacing: 6) {
                ForEach(TimerDraft.steps, id: \.self) { step in
                    Button(TimerDraft.stepTitle(step)) { TimerDraft.adjust(&minutes, by: step) }
                        .monospacedDigit()
                        .frame(maxWidth: .infinity)
                }
            }

            TextField("Label (optional)", text: TimerDraft.limited($label))

            HStack {
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Start") {
                    onStart(duration, TimerDraft.cleanLabel(label))
                    label = ""
                }
                .keyboardShortcut(.defaultAction)
                .disabled(duration <= 0)
            }
        }
        .padding(20)
        .frame(width: 280)
    }

    private func field(_ title: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                TextField(title, text: TimerDraft.digits(value, in: range))
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
                Stepper(title, value: value, in: range)
                    .labelsHidden()
            }
        }
    }
}
