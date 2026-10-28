import AppKit
import SwiftUI

/// One clipboard item up close, opened by clicking it in the list: all of a text, an image bigger,
/// or a color's hex, rgb, hsl and hsv. Files don't open one.
struct BubbleClipboardItemPage: View {
    let history: ClipboardHistory
    let entry: ClipboardEntry

    /// What was just copied ("item", or a color format's symbol), to show a checkmark on it for a moment.
    @State private var justCopied: String?
    @State private var textHeight: CGFloat = 0

    private static let maxTextHeight: CGFloat = 260
    private static let maxImageHeight: CGFloat = 260
    /// Very long copies are cut here so the page stays quick; copying still copies all of it.
    private static let maxShownCharacters = 20_000

    var body: some View {
        VStack(spacing: 6) {
            switch entry.kind {
            case .text(let text):
                if let color = BubbleClipboardPage.hexColor(in: text) {
                    colorDetails(color)
                } else {
                    textDetails(text)
                }
            case .image(let width, let height):
                imageDetails(width: width, height: height)
            case .files:
                EmptyView() // files open nothing; the list copies them
            }
        }
    }

    // MARK: - Text

    private func textDetails(_ text: String) -> some View {
        let shown = text.count > Self.maxShownCharacters ? String(text.prefix(Self.maxShownCharacters)) + "…" : text
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).count
        return VStack(spacing: 6) {
            // Always a ScrollView, sized to the text up to the cap, like the to-do archive.
            ScrollView {
                Text(shown)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { textHeight = $0 }
            }
            .scrollIndicators(.automatic)
            .frame(height: min(textHeight, Self.maxTextHeight))
            .background(RoundedRectangle(cornerRadius: 7).fill(.white))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.black.opacity(0.25), lineWidth: 1.5))

            caption("\(text.count.formatted()) \(text.count == 1 ? "character" : "characters") · \(lines.formatted()) \(lines == 1 ? "line" : "lines")")
            copyItemButton
        }
    }

    // MARK: - Image

    private func imageDetails(width: Int, height: Int) -> some View {
        VStack(spacing: 6) {
            Group {
                if let image = history.image(for: entry) {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 28))
                        .opacity(0.4)
                        .frame(height: 80)
                }
            }
            // As wide as the page, and a tall one no taller than the cap. Never bigger than the image itself.
            .frame(maxWidth: CGFloat(width), maxHeight: min(CGFloat(height), Self.maxImageHeight))
            .background(Color.black.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.black.opacity(0.2), lineWidth: 1))

            caption("\(width)×\(height)")
            copyItemButton
        }
    }

    // MARK: - Color

    /// The formats a color shows, in the Convert tab's units and rounding.
    private static let colorFormats = ["hex", "rgb", "hsl", "hsv"]

    private func colorDetails(_ color: NSColor) -> some View {
        let hexUnit = ColorUnit.named("hex")!
        let rgb = (try? hexUnit.read(BubbleClipboardPage.trimmedText(of: entry)).get()).map(hexUnit.toRGB)
        return VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 7)
                .fill(Color(nsColor: color))
                .frame(height: 56)
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.black.opacity(0.3), lineWidth: 1.5))
            if let rgb {
                VStack(spacing: 4) {
                    ForEach(Self.colorFormats, id: \.self) { symbol in
                        let unit = ColorUnit.named(symbol)!
                        formatRow(symbol, value: unit.show(unit.fromRGB(rgb)))
                    }
                }
            }
        }
    }

    /// "rgb   255, 136, 0   [copy]". Copying a format doesn't add it to the history: it's the same color.
    private func formatRow(_ symbol: String, value: String) -> some View {
        HStack(spacing: 8) {
            Text(symbol)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .opacity(0.5)
                .frame(width: 26, alignment: .leading)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .textSelection(.enabled)
            Spacer(minLength: 0)
            copyIcon(copied: justCopied == symbol) {
                history.copyWithoutSaving(value)
                flash(symbol)
            }
            .help("Copy \(symbol)")
        }
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .padding(.vertical, 3)
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.black.opacity(0.25), lineWidth: 1.5))
    }

    // MARK: - Shared

    private var copyItemButton: some View {
        BubbleButton(justCopied == "item" ? "Copied!" : "Copy", systemImage: justCopied == "item" ? "checkmark" : "doc.on.doc") {
            history.copyToClipboard(entry)
            flash("item")
        }
    }

    /// The small outlined copy button, like the list's.
    private func copyIcon(copied: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 22, height: 22)
                .background(RoundedRectangle(cornerRadius: 5).fill(.white))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(.black, lineWidth: 1.2))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func flash(_ what: String) {
        justCopied = what
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if justCopied == what { justCopied = nil }
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .opacity(0.5)
    }
}
