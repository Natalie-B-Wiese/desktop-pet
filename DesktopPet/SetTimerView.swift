import SwiftUI

/// The "Custom…" timer window: pick minutes and seconds, then Start.
struct SetTimerView: View {
    var onStart: (TimeInterval) -> Void
    var onCancel: () -> Void

    @AppStorage("customTimer.minutes") private var minutes = 20
    @AppStorage("customTimer.seconds") private var seconds = 0

    private var duration: TimeInterval { TimeInterval(minutes * 60 + seconds) }

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 20) {
                field("Minutes", value: $minutes, range: 0...999)
                field("Seconds", value: $seconds, range: 0...59)
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
        let clamped = Binding(
            get: { value.wrappedValue },
            set: { value.wrappedValue = min(max($0, range.lowerBound), range.upperBound) }
        )
        return VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                TextField(title, value: clamped, format: .number)
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
                Stepper(title, value: clamped, in: range)
                    .labelsHidden()
            }
        }
    }
}
