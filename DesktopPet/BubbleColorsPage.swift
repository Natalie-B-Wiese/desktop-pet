import AppKit
import SwiftUI

/// The bubble's color picker: pick a color from anywhere on screen, and keep the last few.
/// Click a color to copy its hex code again.
struct BubbleColorsPage: View {
    let picks: ColorPicks
    var onPick: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            BubbleButton("Pick a color", systemImage: "eyedropper", action: onPick)
                .help("Click anywhere on screen; its hex code is copied")

            if picks.hexes.isEmpty {
                Text("Pick a color from anywhere on screen, and its hex code is copied for you.")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(0.55)
                    .padding(.vertical, 4)
            } else {
                ForEach(picks.hexes, id: \.self) { hex in
                    row(hex)
                }
                BubbleButton("Clear all", systemImage: "trash", action: picks.clear)
            }
        }
    }

    /// An outlined slot: swatch, hex code, and remove. Clicking the slot copies the hex.
    private func row(_ hex: String) -> some View {
        HStack(spacing: 6) {
            Button {
                picks.copy(hex)
            } label: {
                HStack(spacing: 8) {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color(nsColor: NSColor(hex: hex) ?? .gray))
                        .frame(width: 22, height: 22)
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(.black.opacity(0.3), lineWidth: 1))
                    Text("#\(hex)")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    Spacer(minLength: 0)
                    Group {
                        if picks.justCopied == hex {
                            Text("Copied!")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                        } else {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 10, weight: .semibold))
                                .opacity(0.5)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Copy #\(hex)")

            Button {
                picks.delete(hex)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .heavy))
                    .opacity(0.5)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Remove")
        }
        .padding(.leading, 5)
        .padding(.trailing, 3)
        .padding(.vertical, 5)
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.black.opacity(0.25), lineWidth: 1.5))
    }
}
