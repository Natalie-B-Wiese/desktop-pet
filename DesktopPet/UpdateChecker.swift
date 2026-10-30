import AppKit
import Observation
import SwiftUI

/// Asks GitHub once a day whether a newer version is out, and tells you in her bubble.
/// It only says so: downloading and installing are up to you (the Download button opens the release page).
@Observable
final class UpdateChecker {
    struct Release: Equatable {
        let version: String
        /// The release's page on GitHub, with the zip to download.
        let page: URL
    }

    enum Status: Equatable {
        case idle, checking, upToDate, failed
        case available(Release)
    }

    /// What the Settings row shows.
    private(set) var status = Status.idle
    /// The newer version in her bubble, until it's clicked away or downloaded.
    private(set) var notice: Release?

    /// Called when the notice appears or is closed.
    @ObservationIgnored var onNoticeChange: (() -> Void)?

    /// Checks once a day, the only time the app goes online. Settings' button checks right away.
    private static let lastCheckKey = "updates.lastCheck"
    /// The version whose notice was clicked away, so it isn't shown again. A newer one still is.
    private static let dismissedKey = "updates.dismissed"

    private static let latestRelease = URL(string: "https://api.github.com/repos/Natalie-B-Wiese/desktop-pet/releases/latest")!

    /// This app's version ("0.7"). `--pretend-version` overrides it for testing.
    var currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"

    /// The daily check: at most once a day.
    @MainActor
    func checkIfDue() async {
        if let last = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date,
           Calendar.current.isDateInToday(last) { return }
        await check(showsNotice: true)
    }

    /// Settings' Check now button shows the answer in Settings; the daily check puts a newer version in her bubble.
    @MainActor
    func check(showsNotice: Bool, evenIfDismissed: Bool = false) async {
        guard status != .checking else { return }
        status = .checking
        guard let release = await Self.fetchLatest() else {
            status = .failed
            return
        }
        UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)
        guard Self.isNewer(release.version, than: currentVersion) else {
            status = .upToDate
            return
        }
        status = .available(release)
        if showsNotice, evenIfDismissed || UserDefaults.standard.string(forKey: Self.dismissedKey) != release.version {
            notice = release
            onNoticeChange?()
        }
    }

    /// Clicking the bubble away; this version won't be shown in the bubble again.
    func dismissNotice() {
        guard let notice else { return }
        UserDefaults.standard.set(notice.version, forKey: Self.dismissedKey)
        self.notice = nil
        onNoticeChange?()
    }

    /// Opens the release page, and closes the notice (you're on it).
    func download(_ release: Release) {
        NSWorkspace.shared.open(release.page)
        if notice != nil { dismissNotice() }
    }

    private static func fetchLatest() async -> Release? {
        var request = URLRequest(url: latestRelease, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        struct Response: Decodable {
            let tag_name: String
            let html_url: URL
        }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let latest = try? JSONDecoder().decode(Response.self, from: data) else { return nil }
        let version = latest.tag_name.hasPrefix("v") ? String(latest.tag_name.dropFirst()) : latest.tag_name
        return Release(version: version, page: latest.html_url)
    }

    /// Compares "0.10" > "0.9" number by number; missing parts count as 0 ("1.0" = "1").
    static func isNewer(_ version: String, than current: String) -> Bool {
        let a = version.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}

/// "Version 0.8 is out!" in her bubble, with a Download button. Clicking the bubble closes it.
struct BubbleUpdateNotice: View {
    let release: UpdateChecker.Release
    let currentVersion: String
    /// How many more are waiting behind it, like a finished timer.
    let moreCount: Int
    let layout: BubbleLayout
    let download: () -> Void

    var body: some View {
        VStack(spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 9, weight: .bold))
                Text("You have \(currentVersion)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            }
            Text("Version \(release.version) is out!")
                .font(.system(size: 16, weight: .bold, design: .rounded))
            BubbleButton("Download", systemImage: "arrow.down.circle", centered: true, action: download)
                .fixedSize()
                .padding(.vertical, 3)
                .passesBubbleClicks(layout, as: "download")
            Text(moreCount > 0 ? "Click to close · \(moreCount) more" : "Click to close")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .opacity(0.55)
        }
    }
}
