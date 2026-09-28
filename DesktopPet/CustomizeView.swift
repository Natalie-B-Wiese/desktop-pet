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
                Section("Name") {
                    TextField("Name", text: Binding(
                        get: { settings.name },
                        set: { settings.name = String($0.prefix(PetSettings.maxNameLength)) }
                    ), prompt: Text("Name your pet"))
                    .labelsHidden()
                }
                Section("Colors") {
                    colorRow("Main", \.main)
                    colorRow("Secondary", \.secondary)
                    colorRow("Eyes", \.detail)
                }
                Section {
                    sizeSlider
                } header: {
                    sizeHeader
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(height: 370)

            Button("Reset to Default Colors") {
                settings.reset()
            }
            .disabled(settings.palette == .default)
        }
        .padding(20)
        .frame(width: 320)
    }

    private var sizeHeader: some View {
        HStack {
            Text("Size")
            Spacer()
            Text("\(settings.scale)×")
                .monospacedDigit()
            Button("Reset") {
                settings.scale = PetSettings.defaultScale
            }
            .buttonStyle(.link)
            .disabled(settings.scale == PetSettings.defaultScale)
        }
    }

    private var sizeSlider: some View {
        let range = PetSettings.scaleRange
        return Slider(
            value: Binding(
                get: { Double(settings.scale) },
                set: { newValue in
                    let clamped = min(max(Int(newValue.rounded()), range.lowerBound), range.upperBound)
                    if clamped != settings.scale { settings.scale = clamped }
                }
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
        .labelsHidden()
        .frame(maxWidth: .infinity)
    }

    private func colorRow(_ title: String, _ keyPath: WritableKeyPath<PetPalette, NSColor>) -> some View {
        ColorPicker(title, selection: Binding(
            get: { Color(nsColor: settings.palette[keyPath: keyPath]) },
            set: { settings.palette[keyPath: keyPath] = NSColor($0) }
        ), supportsOpacity: false)
    }
}
