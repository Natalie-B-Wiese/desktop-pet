import AppKit
import SwiftUI

/// The bubble's clipboard history: the copy button copies a slot again, ready to paste,
/// and clicking the slot itself opens it up close (text, images and colors). A Record tab records the screen.
struct BubbleClipboardPage: View {
    let history: ClipboardHistory
    let recorder: ScreenRecorder
    var onScreenshot: () -> Void
    var onPickColor: () -> Void
    var onRecord: () -> Void
    var onOpen: (ClipboardEntry.ID) -> Void

    /// The slot that was just copied, to show "Copied!" on it for a moment.
    @State private var justCopied: ClipboardEntry.ID?

    var body: some View {
        VStack(spacing: 8) {
            BubbleTabs(
                selection: Binding(get: { recorder.showsRecordTab }, set: { recorder.showsRecordTab = $0 }),
                options: [(false, "Clipboard"), (true, "Record")]
            )
            if recorder.showsRecordTab {
                BubbleRecordTab(recorder: recorder, onRecord: onRecord)
            } else {
                clipboardTab
            }
        }
    }

    private var clipboardTab: some View {
        VStack(spacing: 6) {

            if history.isAccessDenied {
                note("Clipboard access is off. Turn it on in System Settings → Privacy & Security → Paste from Other Apps.")
            } else if history.entries.isEmpty {
                note("Copy something and it'll show up here.")
            } else {
                let pinned = history.pinnedCount
                let isFull = history.entries.count >= ClipboardHistory.limit
                let normal = Font.system(size: 10, weight: .medium, design: .rounded).monospacedDigit()
                let alert = Font.system(size: 10, weight: .bold, design: .rounded).monospacedDigit()
                let grey = Color.black.opacity(0.5)
                VStack(spacing: 1) {
                    // The count and the warning turn red and bold once full; the rest stays grey.
                    Text("\(history.entries.count)/\(ClipboardHistory.limit)")
                        .font(isFull ? alert : normal)
                        .foregroundStyle(isFull ? Color.red : grey)
                    + Text(pinned > 0 ? " · \(pinned) pinned" : " · New copies appear at the top")
                        .font(normal)
                        .foregroundStyle(grey)
                    if isFull {
                        Text("The next copy will remove the bottom item")
                            .font(alert)
                            .foregroundStyle(.red)
                    }
                    if pinned > 0 {
                        Text("Pinned items stay when you delete all")
                            .font(normal)
                            .foregroundStyle(grey)
                    }
                }
                .padding(.top, -4)
                ForEach(history.entries) { entry in
                    row(entry)
                    // A thin line between the pins and the recent copies.
                    if entry.isPinned, entry.id == history.entries.last(where: \.isPinned)?.id, entry.id != history.entries.last?.id {
                        Rectangle()
                            .fill(Color.black.opacity(0.2))
                            .frame(height: 1)
                            .padding(.horizontal, 4)
                    }
                }
            }

            if !history.isAccessDenied {
                if history.screenshotNeedsPermission {
                    note("To take screenshots, turn on Desktop Pet in System Settings → Privacy & Security → Screen Recording, then quit and reopen the app.")
                }
                // Side by side, since both add a copy to the top slot.
                HStack(spacing: 6) {
                    BubbleButton("Screenshot", systemImage: "camera.viewfinder", centered: true, action: onScreenshot)
                        .help("Select part of the screen; it's copied into the top slot")
                    BubbleButton("Pick color", systemImage: "eyedropper", centered: true, action: onPickColor)
                        .help("Click anywhere on screen; its hex code is copied into the top slot")
                }
            }
            // Pins are kept (the line over the list says so), so with pins it only deletes the unpinned copies.
            if history.entries.count > history.pinnedCount {
                BubbleButton("Delete all", systemImage: "trash", action: history.clear)
                    .help(history.pinnedCount > 0 ? "Deletes every copy except the pinned ones" : "Deletes every copy")
            }

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
        HStack(spacing: 3) {
            // Reorder arrows sit outside the item on the far left, away from the delete button.
            CaretStepper(
                canIncrement: history.canMove(entry.id, by: -1),
                canDecrement: history.canMove(entry.id, by: 1),
                increment: { history.move(entry.id, by: -1) },
                decrement: { history.move(entry.id, by: 1) },
                repeatsWhenHeld: false, // one spot per click
                outlined: false
            )
            .help("Move up or down")

            itemBox(entry)
        }
    }

    /// The outlined slot itself: copy button, preview, and delete.
    private func itemBox(_ entry: ClipboardEntry) -> some View {
        HStack(spacing: 6) {
            Button {
                copy(entry)
            } label: {
                Image(systemName: justCopied == entry.id ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .background(RoundedRectangle(cornerRadius: 5).fill(.white))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(.black, lineWidth: 1.2))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Copy")

            // The whole middle, from the copy button to the pin, opens the item (files just copy, having nothing more to show).
            // Short text and colors fill it with empty space, so they're as easy to click as long ones.
            Button {
                if Self.opens(entry) { onOpen(entry.id) } else { copy(entry) }
            } label: {
                HStack(spacing: 8) {
                    preview(entry)
                    Spacer(minLength: 0)
                    if justCopied == entry.id {
                        Text("Copied!")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .fixedSize()
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointerStyle(.link)
            .help(Self.openHelp(entry))

            let canPin = entry.isPinned || history.canPinMore
            Button {
                history.togglePin(entry.id)
            } label: {
                Image(systemName: entry.isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 10, weight: .bold))
                    .rotationEffect(.degrees(45))
                    .opacity(entry.isPinned ? 1 : (canPin ? 0.5 : 0.2))
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canPin)
            .help(entry.isPinned ? "Unpin" : (canPin ? "Pin to the top so it's never pushed out" : "Unpin one first (\(ClipboardHistory.pinLimit) at most)"))

            if entry.isPinned {
                // No ✕ on a pin, so it can't be deleted by accident; unpin it first. The gap keeps the pins lined up.
                Color.clear.frame(width: 18, height: 18)
            } else {
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
        }
        .padding(.leading, 5)
        .padding(.trailing, 3)
        .padding(.vertical, 5)
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.black.opacity(0.25), lineWidth: 1.5))
    }

    private func copy(_ entry: ClipboardEntry) {
        history.copyToClipboard(entry)
        justCopied = entry.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if justCopied == entry.id { justCopied = nil }
        }
    }

    @ViewBuilder
    private func preview(_ entry: ClipboardEntry) -> some View {
        switch entry.kind {
        case .text(let text) where Self.hexColor(in: text) != nil:
            // A hex color, like "#E8893A", gets a swatch.
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(nsColor: Self.hexColor(in: text)!))
                    .frame(width: 22, height: 22)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.black.opacity(0.3), lineWidth: 1))
                Text(text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased())
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
            }
        case .text(let text):
            // One line, however much was copied, so the list stays short; the up-close page shows all of it.
            Text(Self.flatten(text))
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .lineLimit(1)
                .truncationMode(.tail)
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
                .frame(width: Self.thumbnailSize, height: Self.thumbnailSize)
                .background(Color.black.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.black.opacity(0.2), lineWidth: 1))
                Self.titled("Image", detail: "\(width)×\(height)")
            }
        case .files where ClipboardVideo.url(in: entry) != nil:
            VideoRowPreview(url: ClipboardVideo.url(in: entry)!)
        case .files(let urls):
            HStack(spacing: 6) {
                Image(systemName: urls.count == 1 ? "doc" : "doc.on.doc")
                    .font(.system(size: 14))
                Text(urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) files")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(urls.map(\.lastPathComponent).joined(separator: ", "))
            }
        }
    }

    /// Image and video thumbnails, as tall as the copy button so every row is one line high.
    static let thumbnailSize: CGFloat = 24

    /// "Image  1280×800" on one line: the kind, then a grey detail.
    static func titled(_ title: String, detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .fixedSize()
            Text(detail)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .opacity(0.5)
                .lineLimit(1)
        }
    }

    /// Text, images, colors and videos open up close; other files don't.
    static func opens(_ entry: ClipboardEntry) -> Bool {
        if case .files = entry.kind { return ClipboardVideo.url(in: entry) != nil }
        return true
    }

    private static func openHelp(_ entry: ClipboardEntry) -> String {
        switch entry.kind {
        case .text(let text) where hexColor(in: text) != nil: "See it as hex, rgb, hsl and hsv"
        case .text: "See all of it"
        case .image: "See it bigger"
        case .files where ClipboardVideo.url(in: entry) != nil: "Watch it"
        case .files: "Copy again"
        }
    }

    /// The text without the spaces and line breaks around it; empty for images and files.
    static func trimmedText(of entry: ClipboardEntry) -> String {
        guard case .text(let text) = entry.kind else { return "" }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The color when the text is just a "#RRGGBB" hex code. The "#" is required,
    /// so a plain six-digit number like 123456 isn't mistaken for a color.
    static func hexColor(in text: String) -> NSColor? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 7, trimmed.hasPrefix("#") else { return nil }
        return NSColor(hex: trimmed)
    }

    /// Squeezes line breaks and runs of spaces so the two preview lines show real content.
    private static func flatten(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

/// A video's slot: its first frame, "Video" and its length (the file name shows on hover).
/// A video that was moved or deleted shows faint.
private struct VideoRowPreview: View {
    let url: URL
    @State private var video: ClipboardVideo?
    @State private var isMissing = false

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let thumbnail = video?.thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: isMissing ? "questionmark.square.dashed" : "film")
                        .font(.system(size: 12))
                        .opacity(0.5)
                }
            }
            .frame(width: BubbleClipboardPage.thumbnailSize, height: BubbleClipboardPage.thumbnailSize)
            .background(Color.black.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.black.opacity(0.2), lineWidth: 1))
            BubbleClipboardPage.titled("Video", detail: isMissing ? "Moved or deleted" : video?.lengthText ?? "")
        }
        .opacity(isMissing ? 0.45 : 1)
        .help(url.lastPathComponent)
        .task(id: url) {
            video = await ClipboardVideo.load(url)
            isMissing = video == nil && !ClipboardVideo.exists(url)
        }
    }
}
