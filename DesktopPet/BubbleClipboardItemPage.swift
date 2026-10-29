import AppKit
import SwiftUI

/// One clipboard item up close, opened by clicking it in the list: all of a text, an image bigger,
/// a color's hex, rgb, hsl and hsv, or a video to play. Other files don't open one.
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
                // Only videos open; the list copies other files.
                if let url = ClipboardVideo.url(in: entry) { videoDetails(url) }
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

    // MARK: - Video

    @State private var video: ClipboardVideo?
    @State private var isVideoMissing = false

    /// The player (paused on the first frame), "1280×800 · 0:42 · 12.4 MB", and Copy, Show in Finder and Open.
    private func videoDetails(_ url: URL) -> some View {
        VStack(spacing: 6) {
            if isVideoMissing {
                VStack(spacing: 4) {
                    Image(systemName: "questionmark.square.dashed")
                        .font(.system(size: 26))
                        .opacity(0.4)
                    Text("This video was moved or deleted")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                    Text(url.lastPathComponent)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .opacity(0.5)
                }
                .padding(.vertical, 8)
            } else if let video {
                // As wide as the page, and a tall one no taller than the cap, like images.
                let ratio = video.size.width > 0 && video.size.height > 0 ? video.size.width / video.size.height : 16 / 10
                VideoPlayerBox(url: url)
                    .aspectRatio(ratio, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: Self.maxImageHeight)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.black.opacity(0.2), lineWidth: 1))
                HStack(spacing: 4) {
                    caption(video.infoText)
                    if video.hasSound {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .opacity(0.5)
                            .help("Has sound")
                    }
                }
                .help(url.lastPathComponent)
                copyItemButton
                HStack(spacing: 6) {
                    BubbleButton("Show in Finder", systemImage: "folder", centered: true) {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                    .help("Opens its folder with the video selected")
                    BubbleButton("Open", systemImage: "play.rectangle", centered: true) {
                        NSWorkspace.shared.open(url)
                    }
                    .frame(width: 80)
                    .help("Opens it in its usual app, like QuickTime Player")
                }
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(height: 80)
            }
        }
        .task(id: url) {
            video = await ClipboardVideo.load(url)
            isVideoMissing = video == nil
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
