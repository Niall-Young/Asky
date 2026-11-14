import AppKit
import SwiftUI

private struct ChatSelectionGroupKey: EnvironmentKey {
    static let defaultValue: ChatSelectionGroup? = nil
}
extension EnvironmentValues {
    var chatSelectionGroup: ChatSelectionGroup? {
        get { self[ChatSelectionGroupKey.self] }
        set { self[ChatSelectionGroupKey.self] = newValue }
    }
}

/// One logical text selection across the independently laid-out Markdown blocks of a reply.
/// Weak registrations keep transcript paging and SwiftUI view replacement from retaining messages.
@MainActor
final class ChatSelectionGroup {
    private struct Entry { weak var view: ChatSelectableTextView? }
    private var entries: [Entry] = []
    private weak var anchorView: ChatSelectableTextView?
    private var anchorIndex = 0

    func register(_ view: ChatSelectableTextView) {
        entries.removeAll { $0.view == nil }
        if !entries.contains(where: { $0.view === view }) { entries.append(Entry(view: view)) }
    }

    var orderedViews: [ChatSelectableTextView] {
        entries.compactMap(\.view).filter { $0.window != nil && !$0.isHidden }.sorted {
            let a = $0.convert($0.bounds, to: nil), b = $1.convert($1.bounds, to: nil)
            if abs(a.maxY - b.maxY) > 3 { return a.maxY > b.maxY }
            return a.minX < b.minX
        }
    }

    var selectedText: String {
        var result = ""
        var previous: ChatSelectableTextView?
        for view in orderedViews where view.selectedRange().length > 0 {
            if let previous {
                let a = previous.convert(previous.bounds, to: nil), b = view.convert(view.bounds, to: nil)
                result += abs(a.maxY - b.maxY) < 3 ? "\t" : "\n"
            }
            result += view.localSelectedContent
            previous = view
        }
        return result
    }

    func clear(except kept: ChatSelectableTextView? = nil) {
        for view in entries.compactMap(\.view) where view !== kept {
            view.setSelectedRange(NSRange(location: min(view.selectedRange().location, (view.string as NSString).length), length: 0))
        }
    }

    func selectAll() {
        for view in orderedViews { view.setSelectedRange(NSRange(location: 0, length: (view.string as NSString).length)) }
    }

    private func endpoint(at point: NSPoint) -> (ChatSelectableTextView, Int)? {
        let views = orderedViews
        guard let first = views.first, let last = views.last else { return nil }
        if point.y > first.convert(first.bounds, to: nil).maxY { return (first, 0) }
        if point.y < last.convert(last.bounds, to: nil).minY { return (last, (last.string as NSString).length) }
        let nearest = views.min { a, b in
            func distance(_ view: NSView) -> CGFloat {
                let rect = view.convert(view.bounds, to: nil)
                let dy = max(rect.minY - point.y, point.y - rect.maxY, 0)
                let dx = max(rect.minX - point.x, point.x - rect.maxX, 0)
                return dy * 10_000 + dx
            }
            return distance(a) < distance(b)
        }!
        return (nearest, nearest.characterIndexForInsertion(at: nearest.convert(point, from: nil)))
    }

    @discardableResult
    func extend(to point: NSPoint) -> ChatSelectableTextView? {
        guard let anchorView, let (endView, endIndex) = endpoint(at: point) else { return nil }
        let views = orderedViews
        guard let a = views.firstIndex(where: { $0 === anchorView }),
              let b = views.firstIndex(where: { $0 === endView }) else { return nil }
        let forward = a < b || (a == b && anchorIndex <= endIndex)
        let lower = min(a, b), upper = max(a, b)
        for (index, view) in views.enumerated() {
            let length = (view.string as NSString).length
            if index < lower || index > upper { view.setSelectedRange(NSRange(location: 0, length: 0)); continue }
            let start = index == lower ? (forward ? anchorIndex : endIndex) : 0
            let end = index == upper ? (forward ? endIndex : anchorIndex) : length
            let safeStart = min(max(0, start), length), safeEnd = min(max(0, end), length)
            view.setSelectedRange(NSRange(location: min(safeStart, safeEnd), length: abs(safeEnd - safeStart)))
        }
        if endView.selectedRange().length > 0 { return endView }
        return forward ? views.last(where: { $0.selectedRange().length > 0 }) : views.first(where: { $0.selectedRange().length > 0 })
    }

    /// Returns false for ordinary clicks, preserving NSTextView's links and multi-click behavior.
    func trackDrag(from view: ChatSelectableTextView, event: NSEvent) -> Bool {
        guard orderedViews.count > 1, event.clickCount == 1, let window = view.window else { return false }
        guard let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp],
            until: .distantFuture, inMode: .eventTracking, dequeue: true) else { return false }
        if next.type == .leftMouseUp {
            NSApplication.shared.postEvent(next, atStart: true)
            return false
        }
        if !event.modifierFlags.contains(.shift) || anchorView == nil {
            anchorView = view
            anchorIndex = view.characterIndexForInsertion(at: view.convert(event.locationInWindow, from: nil))
        }
        window.makeFirstResponder(view)
        var latest = next
        var menuOwner: ChatSelectableTextView?
        while true {
            // The document's visible rectangle, rather than one paragraph's bounds, owns autoscroll.
            _ = view.enclosingScrollView?.documentView?.autoscroll(with: latest)
            menuOwner = extend(to: latest.locationInWindow)
            guard latest.type != .leftMouseUp else { break }
            if let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp],
                until: Date(timeIntervalSinceNow: 1.0 / 60), inMode: .eventTracking, dequeue: true) {
                latest = next
            }
            if !window.isVisible { clear(); return true }
        }
        menuOwner?.showSelectionMenu()
        return true
    }
}
