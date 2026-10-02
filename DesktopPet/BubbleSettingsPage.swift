import SwiftUI

/// App-wide preferences that aren't about how the pet looks.
enum AppPreferences {
    /// Show and type times on a 24-hour clock ("14:30") instead of with AM/PM.
    static let militaryTimeKey = "settings.militaryTime"

    static var usesMilitaryTime: Bool { UserDefaults.standard.bool(forKey: militaryTimeKey) }

    /// "2:30 PM", or "14:30" with military time on.
    static func clockText(_ date: Date) -> String {
        guard usesMilitaryTime else { return date.formatted(date: .omitted, time: .shortened) }
        // Built by hand: `.hour(.twoDigits(amPM: .omitted))` still gives 12-hour hours ("02:30" for 14:30)
        // when the Mac is set to a 12-hour clock.
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
}

/// The bubble's "Settings" page.
struct BubbleSettingsPage: View {
    @AppStorage(AppPreferences.militaryTimeKey) private var militaryTime = false

    var body: some View {
        VStack(spacing: 6) {
            Toggle(isOn: $militaryTime) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Military time")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                    Text(militaryTime ? "Times look like 14:30" : "Times look like 2:30 PM")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .opacity(0.55)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toggleStyle(BubbleSwitchStyle())
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.black.opacity(0.25), lineWidth: 1.5))
        }
    }
}

/// An on/off switch drawn like the bubble: black outline, filled black when on.
struct BubbleSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 8) {
                configuration.label
                Capsule()
                    .fill(configuration.isOn ? Color.black : .white)
                    .overlay(Capsule().stroke(.black, lineWidth: 1.5))
                    .frame(width: 34, height: 20)
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle()
                            .fill(.white)
                            .overlay(Circle().stroke(.black, lineWidth: 1.5))
                            .frame(width: 14, height: 14)
                            .padding(3)
                    }
                    .animation(.easeOut(duration: 0.15), value: configuration.isOn)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
