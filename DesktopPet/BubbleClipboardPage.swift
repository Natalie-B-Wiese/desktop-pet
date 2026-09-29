import SwiftUI

/// The bubble's clipboard history: click a slot to copy it again, ready to paste.
struct BubbleClipboardPage: View {
    let history: ClipboardHistory
    var onBack: () -> Void

    /// The slot that was just copied, to show "Copied!" on it for a moment.
    @State private var justCopied: ClipboardEntry.ID?

    var body: some View {
        VStack(spacing: 6) {
            Text("Clipboard")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .padding(.bottom, 2)

            if history.isAccessDenied {
                note("Clipboard access is off. Turn it on in System Settings → Privacy & Security → Paste from Other Apps.")
            } else if history.entries.isEmpty {
                note("Copy something and it'll show up here.")
            } else {
                ForEach(history.entries) { entry in
                    row(entry)
                }
                BubbleButton("Clear all", systemImage: "trash", action: history.clear)
            }

            BubbleButton("Back", systemImage: "chevron.left", style: .quiet, action: onBack)
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .opacity(0.55)
            .padding(.vertical, 4)
    }

    private func row(_ entry: ClipboardEntry) -> some View {
        HStack(spacing: 6) {
            Button {
                history.copyToClipboard(entry)
                justCopied = entry.id
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    if justCopied == entry.id { justCopied = nil }
                }
            } label: {
                HStack(spacing: 8) {
                    preview(entry)
                    Spacer(minLength: 0)
                    if justCopied == entry.id {
                        Text("Copied!")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Copy again")

            Button {
                history.delete(entry.id)
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
        .padding(.leading, 8)
        .padding(.trailing, 3)
        .padding(.vertical, 5)
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.black.opacity(0.25), lineWidth: 1.5))
    }

    @ViewBuilder
    private func preview(_ entry: ClipboardEntry) -> some View {
        switch entry.kind {
        case .text(let text):
            let flattened = Self.flatten(text)
            VStack(alignment: .leading, spacing: 1) {
                // Two lines at most, however much was copied; the full text is still kept.
                Text(flattened)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .multilineTextAlignment(.leading)
                if flattened.count > 60 {
                    caption("\(text.count.formatted()) characters")
                }
            }
        case .image(let width, let height):
            HStack(spacing: 8) {
                Group {
                    if let image = history.image(for: entry) {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        Image(systemName: "photo")
                    }
                }
                .frame(width: 40, height: 40)
                .background(Color.black.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.black.opacity(0.2), lineWidth: 1))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Image")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                    caption("\(width)×\(height)")
                }
            }
        case .files(let urls):
            HStack(spacing: 6) {
                Image(systemName: urls.count == 1 ? "doc" : "doc.on.doc")
                    .font(.system(size: 14))
                VStack(alignment: .leading, spacing: 1) {
                    Text(urls.map(\.lastPathComponent).joined(separator: ", "))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .lineLimit(2)
                        .truncationMode(.middle)
                    if urls.count > 1 { caption("\(urls.count) files") }
                }
            }
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .opacity(0.5)
    }

    /// Squeezes line breaks and runs of spaces so the two preview lines show real content.
    private static func flatten(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
