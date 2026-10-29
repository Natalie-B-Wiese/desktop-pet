import AVKit
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// What the clipboard shows about a video file: its first frame, length, pixel size, file size and whether it has sound.
/// Loaded once per file (and again if the file changes), since reading a movie takes a moment.
struct ClipboardVideo: Equatable {
    var thumbnail: NSImage?
    var seconds: Double
    var size: CGSize
    var bytes: Int64
    var hasSound: Bool

    /// The file, when a clipboard slot is a single video (a recording, or a video copied in Finder).
    static func url(in entry: ClipboardEntry) -> URL? {
        guard case .files(let urls) = entry.kind, urls.count == 1, let url = urls.first,
              let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .movie) else { return nil }
        return url
    }

    static func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    @MainActor private static var cache: [String: (modified: Date?, video: ClipboardVideo)] = [:]

    /// nil if the file is gone or isn't a readable movie.
    @MainActor
    static func load(_ url: URL) async -> ClipboardVideo? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        guard let attributes else { return nil }
        let modified = attributes[.modificationDate] as? Date
        if let cached = cache[url.path], cached.modified == modified { return cached.video }

        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration),
              let tracks = try? await asset.load(.tracks) else { return nil }
        var size = CGSize.zero
        if let track = tracks.first(where: { $0.mediaType == .video }),
           let natural = try? await track.load(.naturalSize), let transform = try? await track.load(.preferredTransform) {
            let turned = natural.applying(transform)
            size = CGSize(width: abs(turned.width), height: abs(turned.height))
        }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 600, height: 600)
        let frame = try? await generator.image(at: .zero).image
        let video = ClipboardVideo(
            thumbnail: frame.map { NSImage(cgImage: $0, size: .zero) },
            seconds: duration.seconds.isFinite ? duration.seconds : 0,
            size: size,
            bytes: (attributes[.size] as? NSNumber)?.int64Value ?? 0,
            hasSound: tracks.contains { $0.mediaType == .audio }
        )
        cache[url.path] = (modified, video)
        return video
    }

    /// "0:42", "12:05", "1:02:09", rounded to the nearest second (at least "0:01").
    var lengthText: String {
        BubbleRecordingTime.text(max(1, Int(seconds.rounded())))
    }

    /// "1280×800 · 0:42 · 12.4 MB".
    var infoText: String {
        let parts = [size == .zero ? nil : "\(Int(size.width))×\(Int(size.height))", lengthText,
                     ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }
}

/// macOS's own video player, with play/pause and a scrubber, paused on the first frame until played.
struct VideoPlayerBox: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> FirstClickPlayerView {
        let view = FirstClickPlayerView()
        view.controlsStyle = .inline
        view.showsFullScreenToggleButton = false // Open plays it full size in QuickTime
        view.videoGravity = .resizeAspect
        view.player = AVPlayer(url: url)
        return view
    }

    func updateNSView(_ view: FirstClickPlayerView, context: Context) {
        if (view.player?.currentItem?.asset as? AVURLAsset)?.url != url {
            view.player = AVPlayer(url: url)
        }
    }

    /// Stops it playing when the page closes.
    static func dismantleNSView(_ view: FirstClickPlayerView, coordinator: ()) {
        view.player?.pause()
        view.player = nil
    }
}

/// The bubble never becomes the active window, so the player must respond to the very first click.
final class FirstClickPlayerView: AVPlayerView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
