import SwiftUI

struct CustomizeView: View {
    let settings: PetSettings

    var body: some View {
        VStack(spacing: 20) {
            Image(nsImage: PetRenderer.render(settings.palette))
                .interpolation(.none)
                .resizable()
                .frame(width: 144, height: 144)
                .padding(12)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))

            Form {
                Section("Colors") {
                    colorRow("Main", \.main)
                    colorRow("Secondary", \.secondary)
                    colorRow("Eyes", \.detail)
                }
                Section("Size") {
                    sizeRow
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(height: 290)

            Button("Reset to Default Colors") {
                settings.reset()
            }
            .disabled(settings.palette == .default)
        }
        .padding(20)
        .frame(width: 320)
    }

    private var sizeRow: some View {
        let range = PetSettings.scaleRange
        return HStack {
            Slider(
                value: Binding(
                    get: { Double(settings.scale) },
                    set: { settings.scale = Int($0.rounded()) }
                ),
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: 1
            ) {
                Text("Size")
            } minimumValueLabel: {
                Image(systemName: "cat.fill").imageScale(.small)
            } maximumValueLabel: {
                Image(systemName: "cat.fill").imageScale(.large)
            }
            Text("\(settings.scale)×")
                .monospacedDigit()
                .frame(width: 32, alignment: .trailing)
                .foregroundStyle(.secondary)
            Button("Reset") {
                settings.scale = PetSettings.defaultScale
            }
            .disabled(settings.scale == PetSettings.defaultScale)
        }
    }

    private func colorRow(_ title: String, _ keyPath: WritableKeyPath<PetPalette, NSColor>) -> some View {
        ColorPicker(title, selection: Binding(
            get: { Color(nsColor: settings.palette[keyPath: keyPath]) },
            set: { settings.palette[keyPath: keyPath] = NSColor($0) }
        ), supportsOpacity: false)
    }
}
