import AVFoundation
import AppKit
import Observation
import ScreenCaptureKit

/// Records part of the screen (or all of it) to a movie file with ScreenCaptureKit, leaving Topsy's own windows
/// out of the video so she can show the time and be clicked while it records. The file is saved to a folder
/// you pick (Movies by default) and put on the clipboard, so clipboard history keeps it as a file slot.
@Observable
final class ScreenRecorder: NSObject {
    enum Audio: String, CaseIterable {
        case none, mic, computer, both

        var title: String {
            switch self {
            case .none: "None"
            case .mic: "Mic"
            case .computer: "Computer"
            case .both: "Both"
            }
        }

        var detail: String {
            switch self {
            case .none: "No sound"
            case .mic: "Your microphone"
            case .computer: "What your Mac plays"
            case .both: "Your mic and your Mac"
            }
        }

        var usesMic: Bool { self == .mic || self == .both }
        var usesComputer: Bool { self == .computer || self == .both }
    }

    static let audioKey = "record.audio"
    static let showsClicksKey = "record.showClicks"
    static let folderKey = "record.folder"

    static var audio: Audio {
        UserDefaults.standard.string(forKey: audioKey).flatMap(Audio.init) ?? .none
    }

    static var showsClicks: Bool { UserDefaults.standard.bool(forKey: showsClicksKey) }

    static let moviesFolder = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0]

    /// The chosen folder, or Movies if none was chosen.
    static var chosenFolder: URL {
        UserDefaults.standard.string(forKey: folderKey).map { URL(fileURLWithPath: $0, isDirectory: true) } ?? moviesFolder
    }

    /// Whether `url` is a folder that's there right now (not deleted, renamed or on an unplugged drive).
    static func folderExists(_ url: URL) -> Bool {
        var isFolder: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder) && isFolder.boolValue
    }

    /// When the recording started; nil when not recording.
    private(set) var startDate: Date?
    var isRecording: Bool { startDate != nil }
    /// Between clicking Record and the video starting: choosing a region, asking for the mic, setting up.
    private(set) var isStarting = false
    /// Screen Recording is off in System Settings.
    var needsScreenPermission = false
    /// The mic was picked, but Microphone access is off.
    var needsMicPermission = false
    /// A grey line on the Record tab about the last recording ("Saved to Movies, since … is missing").
    var note: String?
    /// The Clipboard page's Record tab is showing (not saved: the page opens on it again only while the app runs).
    var showsRecordTab = false
    /// For testing: saves here instead of the chosen folder.
    @ObservationIgnored var folderOverride: URL?

    /// The video file, once it's saved.
    @ObservationIgnored var onFinished: ((URL) -> Void)?
    /// Recording didn't start (`note` says why).
    @ObservationIgnored var onFailed: (() -> Void)?
    /// Called when recording starts or stops, so the bubble can show or hide the time.
    @ObservationIgnored var onChange: (() -> Void)?

    @ObservationIgnored private var stream: SCStream?
    @ObservationIgnored private var output: SCRecordingOutput?
    @ObservationIgnored private var fileURL: URL?

    /// Starts recording `region` (in screen coordinates, on `screen`), or the whole screen when `region` is nil.
    func start(region: NSRect?, on screen: NSScreen) {
        guard !isRecording, !isStarting else { return }
        isStarting = true
        note = nil
        Task { @MainActor in
            do {
                try await begin(region: region, on: screen)
            } catch {
                NSLog("Couldn't start recording: \(error)")
                if note == nil { note = "Couldn't start recording" }
                stream = nil
                output = nil
            }
            isStarting = false
            onChange?()
            if !isRecording { onFailed?() }
        }
    }

    func stop() {
        guard let stream else { return }
        Task { @MainActor in
            do {
                try await stream.stopCapture()
            } catch {
                NSLog("Couldn't stop recording: \(error)")
            }
        }
    }

    @MainActor
    private func begin(region: NSRect?, on screen: NSScreen) async throws {
        let audio = Self.audio
        if audio.usesMic {
            guard await AVCaptureDevice.requestAccess(for: .audio) else {
                needsMicPermission = true
                note = "Couldn't record: Microphone access is off"
                return
            }
        }
        needsMicPermission = false

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let screenID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        guard let display = content.displays.first(where: { $0.displayID == screenID }) ?? content.displays.first else {
            note = "Couldn't find the screen to record"
            return
        }
        // Topsy, her bubbles and anything else of this app stay out of the video.
        let ownApps = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])

        // The region in the display's own points, measured from its top-left corner.
        let scale = screen.backingScaleFactor
        let frame = screen.frame
        let area = region.map {
            CGRect(x: $0.minX - frame.minX, y: frame.maxY - $0.maxY, width: $0.width, height: $0.height).integral
        } ?? CGRect(origin: .zero, size: frame.size)

        let config = SCStreamConfiguration()
        config.sourceRect = area
        // Video sizes must be even.
        config.width = Int(area.width * scale) / 2 * 2
        config.height = Int(area.height * scale) / 2 * 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.showsCursor = true
        config.showMouseClicks = Self.showsClicks
        config.capturesAudio = audio.usesComputer
        config.excludesCurrentProcessAudio = true // her hop sound stays out
        config.captureMicrophone = audio.usesMic

        let url = try nextFileURL()
        let outputConfig = SCRecordingOutputConfiguration()
        outputConfig.outputURL = url
        outputConfig.outputFileType = .mov
        let output = SCRecordingOutput(configuration: outputConfig, delegate: self)

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addRecordingOutput(output)
        self.stream = stream
        self.output = output
        fileURL = url
        try await stream.startCapture()
        startDate = Date()
    }

    /// "Screen Recording 2026-10-29 at 2.31.05 PM.mov", like macOS names its own, in the chosen folder.
    /// A folder that's gone falls back to Movies (and says so), so a recording is never lost.
    private func nextFileURL() throws -> URL {
        var folder = folderOverride ?? Self.chosenFolder
        if !Self.folderExists(folder) {
            note = "Saved to Movies, since \(folder.lastPathComponent) is missing"
            folder = Self.moviesFolder
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        let now = Date()
        let day = now.formatted(.iso8601.year().month().day())
        let time = now.formatted(date: .omitted, time: .standard).replacingOccurrences(of: ":", with: ".")
        let name = "Screen Recording \(day) at \(time)"
        var url = folder.appendingPathComponent("\(name).mov")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(name) \(n).mov")
            n += 1
        }
        return url
    }

    /// The recording ended (Stop, macOS's own stop button, or an error): the file is complete once the output finishes.
    private func finished(error: Error?) {
        DispatchQueue.main.async { [self] in
            guard stream != nil else { return } // already handled
            if let error { NSLog("Recording ended: \(error)") }
            stream = nil
            output = nil
            startDate = nil
            onChange?()
            if let url = fileURL, FileManager.default.fileExists(atPath: url.path) {
                onFinished?(url)
            } else if error != nil {
                note = "The recording couldn't be saved"
            }
            fileURL = nil
        }
    }
}

extension ScreenRecorder: SCRecordingOutputDelegate {
    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        finished(error: nil)
    }

    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        finished(error: error)
    }
}

extension ScreenRecorder: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        // Stopped from macOS's menu bar indicator, or the display went away. The output still
        // finishes the file, so give it a moment before treating the stream itself as the end.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.finished(error: error) }
    }
}
