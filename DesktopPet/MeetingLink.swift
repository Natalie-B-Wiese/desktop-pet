import AppKit
import SwiftUI

/// Finds a meeting's video call link (Zoom, Google Meet or Teams) in its calendar event, and opens it.
enum MeetingLink {
    /// The first call link in the event's URL, location or notes. Google Calendar puts Zoom links in the location
    /// and notes, and Meet links in the notes. A Zoom link wins over the Meet link Google sometimes adds as well.
    static func find(in texts: [String?]) -> URL? {
        let text = texts.compactMap { $0 }.joined(separator: "\n")
        guard !text.isEmpty, let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        let links = detector.matches(in: text, range: NSRange(text.startIndex..., in: text))
            .compactMap(\.url)
            .filter { service(of: $0) != nil }
        let link = links.first { service(of: $0) == "Zoom" } ?? links.first
        // "meet.google.com/abc-defg-hij" with no scheme is read as http.
        guard let link, link.scheme == "http", var secure = URLComponents(url: link, resolvingAgainstBaseURL: false) else { return link }
        secure.scheme = "https"
        return secure.url ?? link
    }

    /// A link typed into a reminder: any web link, with or without `https://` ("zoom.us/j/123" works).
    /// Nil for anything that isn't one, like "tomorrow" or "zoom".
    static func parse(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else { return nil }
        let full = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let url = URL(string: full), ["http", "https"].contains(url.scheme?.lowercased()),
              let host = url.host(), host.contains("."), !host.hasPrefix("."), !host.hasSuffix(".") else { return nil }
        return url
    }

    /// "Zoom", "Meet" or "Teams" for a call link, or nil for any other link.
    static func service(of url: URL) -> String? {
        guard let host = url.host()?.lowercased() else { return nil }
        let path = url.path()
        if host == "zoom.us" || host.hasSuffix(".zoom.us") || host.hasSuffix("zoomgov.com") {
            // Meeting links only, not zoom.us's own pages that invitations also link to.
            return ["/j/", "/my/", "/w/", "/s/"].contains { path.hasPrefix($0) } ? "Zoom" : nil
        }
        if host == "meet.google.com" { return path.count > 1 ? "Meet" : nil }
        if host == "teams.microsoft.com" || host == "teams.live.com" { return path.contains("meet") ? "Teams" : nil }
        return nil
    }

    /// Opens the call. A Zoom meeting goes straight to the Zoom app when it's installed,
    /// skipping the "Open zoom.us?" page in the browser.
    static func open(_ url: URL) {
        NSWorkspace.shared.open(zoomAppURL(for: url) ?? url)
    }

    /// `zoommtg://` for `https://…zoom.us/j/<number>?pwd=…`, or nil without the Zoom app or for other links.
    private static func zoomAppURL(for url: URL) -> URL? {
        guard service(of: url) == "Zoom", let host = url.host(),
              let probe = URL(string: "zoommtg://"), NSWorkspace.shared.urlForApplication(toOpen: probe) != nil else { return nil }
        let parts = url.path().split(separator: "/")
        guard parts.count >= 2, parts[0] == "j", parts[1].allSatisfy(\.isNumber) else { return nil }
        var app = URLComponents()
        app.scheme = "zoommtg"
        app.host = host
        app.path = "/join"
        var query = [URLQueryItem(name: "action", value: "join"), URLQueryItem(name: "confno", value: String(parts[1]))]
        if let pwd = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "pwd" })?.value {
            query.append(URLQueryItem(name: "pwd", value: pwd))
        }
        app.queryItems = query
        return app.url
    }
}

/// "Join Zoom" under a meeting's heads-up or due reminder. It reports where it is so the bubble,
/// which otherwise catches every click as "close", lets clicks on it through.
struct JoinMeetingButton: View {
    let url: URL
    let layout: BubbleLayout

    var body: some View {
        BubbleButton("Join \(MeetingLink.service(of: url) ?? "call")", systemImage: "video.fill", centered: true) {
            MeetingLink.open(url)
        }
        .fixedSize()
        .padding(.vertical, 3)
        .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { layout.joinButtonFrame = $0 }
        .onDisappear { layout.joinButtonFrame = nil }
    }
}
