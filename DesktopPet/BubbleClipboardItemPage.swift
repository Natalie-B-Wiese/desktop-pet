import AppKit
import SwiftUI

/// One clipboard item up close, opened by clicking it in the list: all of a text, an image bigger,
/// a color's hex, rgb, hsl and hsv, a link to open, a video to play, or a file's details (`ClipboardFileDetails`).
struct BubbleClipboardItemPage: View {
    let history: ClipboardHistory
    let entry: ClipboardEntry
    let notes: NoteStore
    /// Opens Add reminder at this time (a copied date's Remind me).
    var onRemind: (Date) -> Void
    /// Opens the Notes page (after Save as note).
    var onOpenNotes: () -> Void

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
                switch ClipboardTextKind.of(text) {
                case .color(let color): colorDetails(color)
                case .link(let url): linkDetails(url)
                case .email(let address): emailDetails(address)
                case .json(let json): jsonDetails(json)
                case .math(let answer, let copy): mathDetails(BubbleClipboardPage.trimmedText(of: entry), answer: answer, copy: copy)
                case .date(let date): dateDetails(date)
                case .text: textDetails(text)
                }
            case .image(let width, let height):
                imageDetails(width: width, height: height)
            case .files(let urls):
                if let url = ClipboardVideo.url(in: entry) {
                    videoDetails(url)
                } else {
                    ClipboardFileDetails(urls: urls) { AnyView(copyItemButton(centered: $0)) }
                }
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
            HStack(spacing: 6) {
                copyItemButton(centered: true)
                saveAsNoteButton(text)
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count > NoteStore.maxLength && !notes.contains(trimmed) {
                caption("Notes hold up to \(NoteStore.maxLength) characters")
            }
        }
    }

    // MARK: - Link

    /// The site big and bold over the whole link (selectable), then Copy and Open, or Join for a call link.
    private func linkDetails(_ url: URL) -> some View {
        let service = MeetingLink.service(of: url)
        let shown = url.absoluteString.count > 2_000 ? String(url.absoluteString.prefix(2_000)) + "…" : url.absoluteString
        return VStack(spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: service != nil ? "video.fill" : "globe")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color.black.opacity(0.06)))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.black.opacity(0.2), lineWidth: 1))
                VStack(alignment: .leading, spacing: 1) {
                    Text(service.map { "\($0) meeting" } ?? BubbleClipboardPage.site(of: url))
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(service != nil ? BubbleClipboardPage.site(of: url) : (url.scheme == "https" ? "Secure link" : "Not a secure link"))
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .opacity(0.5)
                }
                Spacer(minLength: 0)
            }

            // The whole link, wrapping anywhere, in a box like Text's; long ones scroll.
            ScrollView {
                Text(shown)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { textHeight = $0 }
            }
            .scrollIndicators(.automatic)
            .frame(height: min(textHeight, 120))
            .background(RoundedRectangle(cornerRadius: 7).fill(.white))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.black.opacity(0.25), lineWidth: 1.5))

            HStack(spacing: 6) {
                copyItemButton(centered: true)
                if let service {
                    BubbleButton("Join \(service)", systemImage: "video.fill", centered: true) {
                        MeetingLink.open(url)
                    }
                    .help(service == "Zoom" ? "Opens the call in Zoom" : "Opens the call")
                } else {
                    BubbleButton("Open", systemImage: "safari", centered: true) {
                        NSWorkspace.shared.open(url)
                    }
                    .help("Opens it in your browser")
                }
            }
        }
    }

    /// Saves the text as a new note and opens Notes, like Remind me opens Add reminder. If a note already says it,
    /// it reads "In Notes" and just opens Notes, so clicking twice never makes two.
    private func saveAsNoteButton(_ text: String) -> some View {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let saved = notes.contains(trimmed)
        let fits = trimmed.count <= NoteStore.maxLength
        return BubbleButton(saved ? "In Notes" : "Save as note", systemImage: saved ? "checkmark" : "note.text.badge.plus", centered: true) {
            notes.addCopied(trimmed)
            onOpenNotes()
        }
        .disabled(!saved && !fits)
        .opacity(saved || fits ? 1 : 0.4)
        .help(saved ? "A note already says this; opens Notes" : fits ? "Adds it to the top of your notes, then opens Notes" : "")
    }

    // MARK: - Email

    /// The address big and bold, then Copy beside Write email (opens the Mac's mail app with it filled in).
    private func emailDetails(_ address: String) -> some View {
        let parts = address.split(separator: "@", maxSplits: 1).map(String.init)
        return VStack(spacing: 6) {
            header(icon: "envelope", title: parts.first ?? address, subtitle: "@" + (parts.last ?? ""))
                .help(address)
            HStack(spacing: 6) {
                copyItemButton(centered: true)
                BubbleButton("Write email", systemImage: "square.and.pencil", centered: true) {
                    if let url = URL(string: "mailto:" + address) { NSWorkspace.shared.open(url) }
                }
                .help("Opens your mail app with a new email to \(address)")
            }
        }
    }

    // MARK: - Date

    /// "Thursday, Nov 12" big, the time, how far off it is, then Copy and Remind me.
    private func dateDetails(_ date: ClipboardDate) -> some View {
        VStack(spacing: 6) {
            VStack(spacing: 1) {
                Text(date.dayText)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                if let time = date.timeText {
                    Text(time)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                }
                caption(date.relativeText())
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.black.opacity(0.25), lineWidth: 1.5))

            HStack(spacing: 6) {
                copyItemButton(centered: true)
                BubbleButton("Remind me", systemImage: "bell.badge", centered: true) {
                    onRemind(date.date)
                }
                .disabled(!date.canRemind)
                .opacity(date.canRemind ? 1 : 0.4)
                .help(date.canRemind ? "Opens Add reminder at this time" : "")
            }
            if !date.canRemind {
                caption(date.hasTime ? "Reminders can only be set for the next 24 hours" : "Reminders need a time, like 2pm")
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - JSON

    /// Tidied, one item per line, in a box; copy it tidied or on one line.
    private func jsonDetails(_ json: ClipboardJSON) -> some View {
        let lines = json.tidied.split(separator: "\n", omittingEmptySubsequences: false).count
        let shown = json.tidied.count > Self.maxShownCharacters ? String(json.tidied.prefix(Self.maxShownCharacters)) + "…" : json.tidied
        return VStack(spacing: 6) {
            ScrollView {
                Text(shown)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
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

            caption("\(json.summary) · \(lines.formatted()) \(lines == 1 ? "line" : "lines")")
            // Copying a layout doesn't add it to the history: it's the same JSON.
            HStack(spacing: 6) {
                BubbleButton(justCopied == "tidied" ? "Copied!" : "Tidied", systemImage: justCopied == "tidied" ? "checkmark" : "doc.on.doc", centered: true) {
                    history.copyWithoutSaving(json.tidied)
                    flash("tidied")
                }
                .help("Copy it tidied, one item per line")
                BubbleButton(justCopied == "oneLine" ? "Copied!" : "One line", systemImage: justCopied == "oneLine" ? "checkmark" : "doc.on.doc", centered: true) {
                    history.copyWithoutSaving(json.oneLine)
                    flash("oneLine")
                }
                .help("Copy it all on one line")
            }
        }
    }

    // MARK: - Math

    /// The sum, its answer big and bold, and Copy answer (without commas, so it pastes as a number).
    private func mathDetails(_ sum: String, answer: String, copy: String) -> some View {
        VStack(spacing: 6) {
            VStack(spacing: 2) {
                Text(sum)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .opacity(0.6)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                Text("= " + answer)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.5)
                    .textSelection(.enabled)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.black.opacity(0.25), lineWidth: 1.5))

            HStack(spacing: 6) {
                copyItemButton(centered: true)
                BubbleButton(justCopied == "answer" ? "Copied!" : "Copy answer", systemImage: justCopied == "answer" ? "checkmark" : "equal", centered: true) {
                    history.copyWithoutSaving(copy)
                    flash("answer")
                }
                .help("Copies \(copy)")
            }
        }
    }

    /// A big icon in a box beside a bold title and a grey line, like the Link page's.
    private func header(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.black.opacity(0.06)))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.black.opacity(0.2), lineWidth: 1))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Text(subtitle)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .opacity(0.5)
            }
            Spacer(minLength: 0)
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

    private var copyItemButton: some View { copyItemButton(centered: false) }

    private func copyItemButton(centered: Bool) -> some View {
        BubbleButton(justCopied == "item" ? "Copied!" : "Copy", systemImage: justCopied == "item" ? "checkmark" : "doc.on.doc", centered: centered) {
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
