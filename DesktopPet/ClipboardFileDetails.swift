import AppKit
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

/// What the clipboard shows about a copied file or folder: its kind, size and where it is.
struct ClipboardFileInfo {
    let url: URL
    let exists: Bool
    let isFolder: Bool
    /// macOS's own name for the kind, like "PDF document" or "Folder".
    let kind: String
    /// A file's size, or nil for a folder.
    let bytes: Int64?
    /// How many items a folder holds (hidden ones left out), or nil for a file.
    let itemCount: Int?

    init(_ url: URL) {
        self.url = url
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .fileSizeKey, .totalFileSizeKey, .localizedTypeDescriptionKey])
        exists = FileManager.default.fileExists(atPath: url.path)
        // An app or other package is one thing to the user, not a folder to look into.
        isFolder = (values?.isDirectory ?? false) && !(values?.isPackage ?? false)
        kind = values?.localizedTypeDescription ?? UTType(filenameExtension: url.pathExtension)?.localizedDescription ?? "File"
        bytes = isFolder ? nil : (values?.totalFileSize ?? values?.fileSize).map(Int64.init)
        itemCount = isFolder ? (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: .skipsHiddenFiles))?.count : nil
    }

    var isAudio: Bool { UTType(filenameExtension: url.pathExtension)?.conforms(to: .audio) ?? false }

    /// "2.4 MB", or "12 items" for a folder.
    var sizeText: String? {
        if let itemCount { return "\(itemCount.formatted()) \(itemCount == 1 ? "item" : "items")" }
        return bytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
    }

    /// "Downloads", or "Home" for the home folder itself.
    var folderName: String {
        let parent = url.deletingLastPathComponent()
        return parent.path == FileManager.default.homeDirectoryForCurrentUser.path ? "Home" : FileManager.default.displayName(atPath: parent.path)
    }

    var icon: NSImage { NSWorkspace.shared.icon(forFile: url.path) }
}

/// One copied file or folder up close (a Quick Look preview, or a player for sound), or several as a list.
/// Videos have their own page.
struct ClipboardFileDetails: View {
    let urls: [URL]
    /// The page's Copy button; true centers its label, for a button beside another.
    let copyButton: (_ centered: Bool) -> AnyView

    var body: some View {
        if urls.count == 1 {
            SingleFileDetails(info: ClipboardFileInfo(urls[0]), copyButton: copyButton)
        } else {
            SeveralFilesDetails(infos: urls.map(ClipboardFileInfo.init), copyButton: copyButton)
        }
    }

    static func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .opacity(0.5)
    }

    static func missing(_ name: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: "questionmark.square.dashed")
                .font(.system(size: 26))
                .opacity(0.4)
            Text("This file was moved or deleted")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
            Text(name)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(0.5)
        }
        .padding(.vertical, 8)
    }
}

private struct SingleFileDetails: View {
    let info: ClipboardFileInfo
    /// The page's Copy button; true centers its label, for a button beside another.
    let copyButton: (_ centered: Bool) -> AnyView

    @State private var preview: NSImage?
    @State private var sound: ClipboardVideo?

    private static let maxPreviewHeight: CGFloat = 160

    var body: some View {
        VStack(spacing: 6) {
            if !info.exists {
                ClipboardFileDetails.missing(info.url.lastPathComponent)
            } else {
                if info.isAudio {
                    audioPlayer
                } else if let preview {
                    // A page, picture or document as wide as the page; never bigger than the preview itself.
                    Image(nsImage: preview)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: preview.size.width, maxHeight: min(preview.size.height, Self.maxPreviewHeight))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.black.opacity(0.2), lineWidth: 1))
                } else {
                    // Its Finder icon, for folders, apps and anything Quick Look can't draw.
                    Image(nsImage: info.icon)
                        .resizable()
                        .frame(width: 64, height: 64)
                }

                Text(info.url.lastPathComponent)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                ClipboardFileDetails.caption(([info.kind, sound?.lengthText, info.sizeText].compactMap { $0 }).joined(separator: " · "))
                Label(info.folderName, systemImage: "folder")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .opacity(0.5)
                    .help(info.url.deletingLastPathComponent().path)
            }
            copyButton(false)
            if info.exists {
                HStack(spacing: 6) {
                    BubbleButton("Show in Finder", systemImage: "folder", centered: true) {
                        NSWorkspace.shared.activateFileViewerSelecting([info.url])
                    }
                    .help(info.isFolder ? "Opens the folder it's in, with it selected" : "Opens its folder with it selected")
                    BubbleButton("Open", systemImage: info.isFolder ? "folder.fill" : "arrow.up.forward.app", centered: true) {
                        NSWorkspace.shared.open(info.url)
                    }
                    .frame(width: 80)
                    .help(info.isFolder ? "Opens it in Finder" : "Opens it in its usual app")
                }
            }
        }
        .task(id: info.url) {
            guard info.exists else { return }
            if info.isAudio {
                sound = await ClipboardVideo.load(info.url)
            } else if !info.isFolder {
                preview = await Self.quickLook(info.url)
            }
        }
    }

    /// macOS's player with its scrubber, paused until played, under the file's icon.
    private var audioPlayer: some View {
        VStack(spacing: 6) {
            Image(nsImage: info.icon)
                .resizable()
                .frame(width: 48, height: 48)
            VideoPlayerBox(url: info.url)
                .frame(height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.black.opacity(0.2), lineWidth: 1))
        }
    }

    /// Quick Look's picture of the file (a PDF's first page, a document, an image), or nil when it only has an icon.
    private static func quickLook(_ url: URL) async -> NSImage? {
        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: CGSize(width: 226, height: maxPreviewHeight),
            scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .thumbnail
        )
        guard let thumbnail = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else { return nil }
        return thumbnail.nsImage
    }
}

/// Several files copied at once: each one's icon, name and size (clicking one shows it in Finder), and the total.
private struct SeveralFilesDetails: View {
    let infos: [ClipboardFileInfo]
    /// The page's Copy button; true centers its label, for a button beside another.
    let copyButton: (_ centered: Bool) -> AnyView

    @State private var listHeight: CGFloat = 0

    var body: some View {
        let found = infos.filter(\.exists)
        let total = found.compactMap(\.bytes).reduce(0, +)
        VStack(spacing: 6) {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(infos.enumerated()), id: \.offset) { index, info in
                        if index > 0 {
                            Rectangle().fill(Color.black.opacity(0.1)).frame(height: 1)
                        }
                        row(info)
                    }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
            }
            .scrollIndicators(.automatic)
            .frame(height: min(listHeight, 220))
            .background(RoundedRectangle(cornerRadius: 7).fill(.white))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.black.opacity(0.25), lineWidth: 1.5))

            ClipboardFileDetails.caption(
                "\(infos.count) files" + (total > 0 ? " · " + ByteCountFormatter.string(fromByteCount: total, countStyle: .file) : "")
                    + (found.count < infos.count ? " · \(infos.count - found.count) missing" : "")
            )
            HStack(spacing: 6) {
                copyButton(true)
                BubbleButton("Show in Finder", systemImage: "folder", centered: true) {
                    NSWorkspace.shared.activateFileViewerSelecting(found.map(\.url))
                }
                .disabled(found.isEmpty)
                .help("Opens Finder with them all selected")
            }
        }
    }

    private func row(_ info: ClipboardFileInfo) -> some View {
        Button {
            NSWorkspace.shared.activateFileViewerSelecting([info.url])
        } label: {
            HStack(spacing: 6) {
                Image(nsImage: info.icon)
                    .resizable()
                    .frame(width: 18, height: 18)
                Text(info.url.lastPathComponent)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 4)
                Text(info.exists ? info.sizeText ?? "" : "Moved or deleted")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .opacity(0.5)
                    .fixedSize()
            }
            .opacity(info.exists ? 1 : 0.45)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointerStyle(.link)
        .disabled(!info.exists)
        .help(info.exists ? "Show \(info.url.lastPathComponent) in Finder" : info.url.path)
    }
}
