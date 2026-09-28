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
                colorRow("Main", \.main)
                colorRow("Secondary", \.secondary)
                colorRow("Eyes", \.detail)
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(height: 160)

            Button("Reset to Default Colors") {
                settings.reset()
            }
            .disabled(settings.palette == .default)
        }
        .padding(20)
        .frame(width: 320)
    }

    private func colorRow(_ title: String, _ keyPath: WritableKeyPath<PetPalette, NSColor>) -> some View {
        ColorPicker(title, selection: Binding(
            get: { Color(nsColor: settings.palette[keyPath: keyPath]) },
            set: { settings.palette[keyPath: keyPath] = NSColor($0) }
        ), supportsOpacity: false)
    }
}
