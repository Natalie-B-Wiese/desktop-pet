import AppKit
import SwiftUI

/// The Clipboard page's Record tab: the Record button and its options (sound, click rings, where videos are saved).
struct BubbleRecordTab: View {
    @Bindable var recorder: ScreenRecorder
    var onRecord: () -> Void

    @AppStorage(ScreenRecorder.audioKey) private var audio = ScreenRecorder.Audio.none.rawValue
    @AppStorage(ScreenRecorder.showsClicksKey) private var showsClicks = false
    @AppStorage(ScreenRecorder.folderKey) private var folderPath = ""

    var body: some View {
        // Like macOS's Save dialog: the name and folder first, then the options, then the button at the bottom
        // (as on the Clipboard tab).
        VStack(spacing: 6) {
            saveBox
            audioPicker
            Toggle(isOn: $showsClicks) {
                titled("Show clicks", detail: "A ring where you click")
            }
            .toggleStyle(BubbleSwitchStyle())
            .disabled(recorder.isRecording)
            .boxed()

            if let start = recorder.startDate {
                BubbleButton("Stop recording", systemImage: "stop.circle", action: recorder.stop)
                    .overlay(alignment: .trailing) {
                        BubbleRecordingTime(start: start, compact: true)
                            .padding(.trailing, 10)
                            .allowsHitTesting(false)
                    }
                    .help("Saves the video and puts it on the clipboard")
            } else {
                BubbleButton("Record screen", systemImage: "record.circle", action: onRecord)
                    .disabled(recorder.isStarting || ScreenRecorder.nameProblem(recorder.fileName) != nil)
                    .opacity(ScreenRecorder.nameProblem(recorder.fileName) == nil ? 1 : 0.4)
                    .help("Drag over part of the screen, or click for all of it. Esc cancels.")
            }
            if recorder.needsScreenPermission {
                note("To record, turn on Desktop Pet in System Settings → Privacy & Security → Screen Recording, then quit and reopen the app.")
            } else if recorder.needsMicPermission {
                note("To record your mic, turn on Desktop Pet in System Settings → Privacy & Security → Microphone.")
            } else if let text = recorder.note {
                note(text)
            }
        }
        // Settings can't change mid-recording; they apply to the next one.
        .animation(nil, value: recorder.isRecording)
    }

    /// "Sound  ‹ Mic ›", stepping through the choices and wrapping around, like the rows in Settings.
    private var audioPicker: some View {
        let current = ScreenRecorder.Audio(rawValue: audio) ?? .none
        return HStack(spacing: 0) {
            titled("Sound", detail: current.detail)
            Spacer(minLength: 0)
            HStack(spacing: 0) {
                HeaderIconButton(systemImage: "chevron.left", help: "Previous", width: 18) { step(-1) }
                Text(current.title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .frame(width: 64)
                HeaderIconButton(systemImage: "chevron.right", help: "Next", width: 18) { step(1) }
            }
            .disabled(recorder.isRecording)
        }
        .boxed()
    }

    private func step(_ by: Int) {
        let all = ScreenRecorder.Audio.allCases
        let index = all.firstIndex(of: ScreenRecorder.Audio(rawValue: audio) ?? .none) ?? 0
        audio = all[(index + by + all.count) % all.count].rawValue
    }

    /// "Save as [Demo] .mov / in 📁 Movies Change…", read as one sentence. The name is optional (empty uses the date
    /// and time, like macOS's own recordings). A name that's taken says what it'll be saved as instead; nothing is
    /// overwritten. A folder that's gone shows faint; the next video goes to Movies.
    private var saveBox: some View {
        let name = ScreenRecorder.cleanName(recorder.fileName)
        let folder = folderPath.isEmpty ? ScreenRecorder.moviesFolder : URL(fileURLWithPath: folderPath, isDirectory: true)
        let exists = ScreenRecorder.folderExists(folder)
        let saveFolder = recorder.saveFolder
        let problem = ScreenRecorder.nameProblem(name)
        let free = name.isEmpty || problem != nil ? nil : ScreenRecorder.freeURL(named: name, in: saveFolder)
        let labelWidth: CGFloat = 50
        return VStack(spacing: 3) {
            VStack(spacing: 6) {
                HStack(spacing: 4) {
                    label("Save as", width: labelWidth)
                    TextField("Date and time", text: $recorder.fileName)
                        .bubbleFieldStyle()
                        .disabled(recorder.isRecording || recorder.isStarting)
                        .onChange(of: recorder.fileName) {
                            if recorder.fileName.count > ScreenRecorder.fileNameLimit {
                                recorder.fileName = String(recorder.fileName.prefix(ScreenRecorder.fileNameLimit))
                            }
                        }
                        .help("The video's file name. Leave it empty for the date and time, like macOS's own recordings.")
                    Text(".mov")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .opacity(0.45)
                        .fixedSize()
                }
                HStack(spacing: 4) {
                    label("in", width: labelWidth)
                    HStack(spacing: 4) {
                        Image(systemName: exists ? "folder" : "questionmark.folder")
                            .font(.system(size: 11, weight: .semibold))
                        Text(FileManager.default.displayName(atPath: folder.path))
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .opacity(exists ? 1 : 0.45)
                    .help(exists ? folder.path : "\(folder.path) is missing, so videos go to Movies")
                    Spacer(minLength: 0)
                    Button("Change…", action: chooseFolder)
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(.black, lineWidth: 1.2))
                        .contentShape(Rectangle())
                        .help("Pick the folder videos are saved to")
                        .disabled(recorder.isRecording)
                }
            }
            .boxed()
            if let problem {
                warning(problem)
            } else if let free, free.deletingPathExtension().lastPathComponent != name {
                warning("\(FileManager.default.displayName(atPath: saveFolder.path)) already has a video named \(name). This one will be \(free.deletingPathExtension().lastPathComponent).")
            }
        }
    }

    private func label(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .frame(width: width, alignment: .leading)
    }

    /// Red and bold, like the Clipboard's full warning.
    private func warning(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(.red)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// macOS's folder picker, starting in the current folder.
    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose where screen recordings are saved"
        let current = ScreenRecorder.chosenFolder
        panel.directoryURL = ScreenRecorder.folderExists(current) ? current : ScreenRecorder.moviesFolder
        panel.level = .floating + 1 // above Topsy and her bubble
        NSApp.activate()
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            // Movies is the default, so picking it again just forgets the choice.
            folderPath = url.standardizedFileURL == ScreenRecorder.moviesFolder.standardizedFileURL ? "" : url.path
            recorder.note = nil
        }
    }

    private func titled(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
            Text(detail)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .opacity(0.55)
        }
        .fixedSize()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .opacity(0.55)
            .padding(.vertical, 2)
    }
}

private extension View {
    /// The faint outlined box around each row, like Settings'.
    func boxed() -> some View {
        padding(.horizontal, 10)
            .padding(.vertical, 6)
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.black.opacity(0.25), lineWidth: 1.5))
    }
}

/// "● 0:42" while recording: a blinking red dot and the time so far. In the bubble it adds "Click to stop".
struct BubbleRecordingTime: View {
    let start: Date
    var compact = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let seconds = max(0, Int(context.date.timeIntervalSince(start)))
            VStack(spacing: 1) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: compact ? 8 : 10, height: compact ? 8 : 10)
                        .opacity(seconds % 2 == 0 || compact ? 1 : 0.35)
                    Text(Self.text(seconds))
                        .font(.system(size: compact ? 12 : 16, weight: .bold, design: .rounded).monospacedDigit())
                }
                if !compact {
                    Text("Click to stop recording")
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .opacity(0.55)
                }
            }
        }
    }

    /// "0:42", "12:05", "1:02:09".
    static func text(_ seconds: Int) -> String {
        let (h, m, s) = (seconds / 3600, seconds / 60 % 60, seconds % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}
