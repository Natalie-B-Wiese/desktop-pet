import AppKit
import SwiftUI

/// Links in notes: underlined in blue, and opened with ⌘-click (a plain click still edits, like Notes.app).
/// SwiftUI's TextEditor can't style or open links on macOS 15, so this finds the editor's own `NSTextView`
/// and styles its text storage directly. Only attributes change, never the text, so the editor's binding
/// and cursor are left alone.
enum NoteLinks {
    static let color = NSColor(red: 0.1, green: 0.35, blue: 0.85, alpha: 1)
    private static let identifier = NSUserInterfaceItemIdentifier("noteText")
    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    private static var monitor: Any?
    private static var cursorMonitor: Any?

    /// The web links (and email addresses) in `text`.
    static func links(in text: String) -> [(range: NSRange, url: URL)] {
        guard let detector else { return [] }
        return detector.matches(in: text, range: NSRange(location: 0, length: (text as NSString).length))
            .compactMap { match in match.url.map { (match.range, $0) } }
    }

    /// Underlines the links in a note's text view and clears the look everywhere else (e.g. a link just edited away).
    static func style(_ textView: NSTextView, baseColor: NSColor) {
        textView.identifier = identifier
        installMonitor()
        guard let storage = textView.textStorage else { return }
        let whole = NSRange(location: 0, length: storage.length)
        let found = links(in: storage.string)
        let current = (0..<storage.length).isEmpty ? [] : linkRanges(in: storage)
        guard current != found.map(\.range) else { return } // nothing changed; skip the redraw
        storage.beginEditing()
        storage.removeAttribute(.underlineStyle, range: whole)
        storage.addAttribute(.foregroundColor, value: baseColor, range: whole)
        for link in found {
            storage.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: link.range)
            storage.addAttribute(.foregroundColor, value: color, range: link.range)
        }
        storage.endEditing()
        // Typing right after a link shouldn't carry on its underline.
        textView.typingAttributes[.underlineStyle] = nil
        textView.typingAttributes[.foregroundColor] = baseColor
    }

    /// The ranges currently underlined, to tell whether anything needs restyling.
    private static func linkRanges(in storage: NSTextStorage) -> [NSRange] {
        var ranges: [NSRange] = []
        storage.enumerateAttribute(.underlineStyle, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            if value != nil { ranges.append(range) }
        }
        return ranges
    }

    /// One watcher for the whole app: a ⌘-click on a link in a note opens it and goes no further.
    private static func installMonitor() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            guard event.modifierFlags.contains(.command), let url = link(under: event) else { return event }
            MeetingLink.open(url) // call links go straight to the Zoom app, like everywhere else
            return nil
        }
        // With ⌘ held over a link, the text view would put its I-beam back on every mouse move and cursor
        // update, so the hand flickered. Those events are kept from it there, and the hand is set instead.
        cursorMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .cursorUpdate, .flagsChanged]) { event in
            guard NSEvent.modifierFlags.contains(.command), let window = event.window,
                  link(at: window.mouseLocationOutsideOfEventStream, of: window) != nil else { return event }
            NSCursor.pointingHand.set()
            return event.type == .flagsChanged ? event : nil
        }
    }

    private static func link(under event: NSEvent) -> URL? {
        guard let window = event.window else { return nil }
        return link(at: event.locationInWindow, of: window)
    }

    /// The link under a point in a window, if it's in one of the notes' text views.
    static func link(at windowPoint: NSPoint, of window: NSWindow) -> URL? {
        guard let contentView = window.contentView,
              let hit = contentView.hitTest(contentView.convert(windowPoint, from: nil)) else { return nil }
        var view: NSView? = hit
        while let v = view, !(v is NSTextView) { view = v.superview }
        guard let textView = view as? NSTextView, textView.identifier == identifier else { return nil }
        return link(at: windowPoint, in: textView)
    }

    /// The link at a point in the window, in one of the notes' text views.
    static func link(at windowPoint: NSPoint, in textView: NSTextView) -> URL? {
        let point = textView.convert(windowPoint, from: nil)
        guard textView.bounds.contains(point) else { return nil }
        let index = textView.characterIndexForInsertion(at: point)
        // characterIndexForInsertion rounds to the nearest gap, so a click on a link's last letter can land just past it.
        return links(in: textView.string).first { NSLocationInRange(index, $0.range) || index == NSMaxRange($0.range) && index > $0.range.location }?.url
    }
}

/// Placed over a note's TextEditor: finds the `NSTextView` drawn there and keeps its links styled.
struct NoteLinkStyler: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> ProbeView { ProbeView() }

    func updateNSView(_ view: ProbeView, context: Context) {
        // After SwiftUI has passed the new text to the editor.
        DispatchQueue.main.async { view.restyle() }
    }

    final class ProbeView: NSView {
        private weak var textView: NSTextView?
        /// The editor's own text color, read before any styling, to put back where a link was.
        private var baseColor: NSColor = .black

        override func hitTest(_ point: NSPoint) -> NSView? { nil } // clicks go to the editor underneath

        // MARK: The hand cursor while ⌘ is held over a link

        /// Checks the mouse and ⌘ while the mouse is over this note (⌘ can be pressed without moving the mouse,
        /// and the bubble rarely gets key events, so this looks instead of waiting for events).
        private var hoverTimer: Timer?
        private var showsHand = false

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
        }

        override func mouseEntered(with event: NSEvent) {
            hoverTimer?.invalidate()
            hoverTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in self?.updateCursor() }
            updateCursor()
        }

        override func mouseExited(with event: NSEvent) { stopHover() }

        private func stopHover() {
            hoverTimer?.invalidate()
            hoverTimer = nil
            if showsHand { window?.enableCursorRects(); NSCursor.arrow.set() }
            showsHand = false
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            super.viewWillMove(toWindow: newWindow)
            if newWindow == nil { stopHover() }
        }

        private func updateCursor() {
            guard let window, let textView else { return }
            let overLink = NSEvent.modifierFlags.contains(.command)
                && NoteLinks.link(at: window.mouseLocationOutsideOfEventStream, in: textView) != nil
            if overLink && !showsHand {
                window.disableCursorRects() // the text view's I-beam area would win otherwise
                NSCursor.pointingHand.set()
            } else if overLink && NSCursor.current != NSCursor.pointingHand {
                NSCursor.pointingHand.set() // something else changed it; put the hand back
            } else if !overLink && showsHand {
                window.enableCursorRects()
                NSCursor.iBeam.set()
            }
            showsHand = overLink
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { self.restyle() }
        }

        override func layout() {
            super.layout()
            if textView == nil { DispatchQueue.main.async { self.restyle() } }
        }

        func restyle() {
            if textView?.window == nil {
                textView = findTextView()
                if let color = textView?.typingAttributes[.foregroundColor] as? NSColor { baseColor = color }
            }
            if let textView { NoteLinks.style(textView, baseColor: baseColor) }
        }

        /// The text view whose frame best overlaps this probe's (each note's editor sits right under its probe).
        private func findTextView() -> NSTextView? {
            guard let window, let root = window.contentView else { return nil }
            let mine = convert(bounds, to: nil)
            guard mine.width > 0, mine.height > 0 else { return nil }
            var best: (view: NSTextView, area: CGFloat)?
            func walk(_ view: NSView) {
                if let textView = view as? NSTextView {
                    let frame = (textView.enclosingScrollView ?? textView).convert((textView.enclosingScrollView ?? textView).bounds, to: nil)
                    let overlap = frame.intersection(mine)
                    let area = overlap.isNull ? 0 : overlap.width * overlap.height
                    if area > (best?.area ?? 0) { best = (textView, area) }
                }
                view.subviews.forEach(walk)
            }
            walk(root)
            return best?.view
        }
    }
}
