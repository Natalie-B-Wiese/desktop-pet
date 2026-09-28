import SwiftUI

/// The minutes and seconds last picked, shared by the bubble's timer page and the Set Timer window.
enum TimerDraft {
    static let minutesKey = "customTimer.minutes"
    static let secondsKey = "customTimer.seconds"
    static let defaultMinutes = 20

    static let minuteRange = 0...999
    static let secondRange = 0...59

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

/// The "Custom…" timer window: pick minutes and seconds, then Start.
struct SetTimerView: View {
    var onStart: (TimeInterval) -> Void
    var onCancel: () -> Void

    @AppStorage(TimerDraft.minutesKey) private var minutes = TimerDraft.defaultMinutes
    @AppStorage(TimerDraft.secondsKey) private var seconds = 0

    private var duration: TimeInterval { TimeInterval(minutes * 60 + seconds) }

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 20) {
                field("Minutes", value: $minutes, range: TimerDraft.minuteRange)
                field("Seconds", value: $seconds, range: TimerDraft.secondRange)
            }

            HStack(spacing: 6) {
                ForEach(TimerDraft.steps, id: \.self) { step in
                    Button(TimerDraft.stepTitle(step)) { TimerDraft.adjust(&minutes, by: step) }
                        .monospacedDigit()
                        .frame(maxWidth: .infinity)
                }
            }

            HStack {
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Start") { onStart(duration) }
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
