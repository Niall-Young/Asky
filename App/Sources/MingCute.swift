import AppKit
import SwiftUI

/// Bundled MingCute vectors; compatibility keys preserve existing semantic icon choices.
/// Keep this mapping in sync with scripts/mingcute-icons.json.
enum MingCute {
    static let assets: [String: String] = [
        "magnifyingglass": "MingCute-search",
        "xmark": "MingCute-close",
        "xmark.circle": "MingCute-close_circle",
        "xmark.circle.fill": "MingCute-filled-close_circle",
        "checkmark": "MingCute-check",
        "checklist": "MingCute-list_check",
        "checkmark.shield": "MingCute-custom-approval-hand",
        "exclamationmark.shield": "MingCute-safe_alert",
        "exclamationmark.triangle": "MingCute-warning",
        "pin": "MingCute-pin",
        "pin.fill": "MingCute-filled-pin",
        "chevron.left": "MingCute-left",
        "chevron.right": "MingCute-right",
        "chevron.down": "MingCute-down",
        "chevron.up": "MingCute-up",
        "ellipsis.circle": "MingCute-more_3",
        "ellipsis.vertical": "MingCute-more_2",
        "plus": "MingCute-add",
        "trash": "MingCute-delete_2",
        "arrow.clockwise": "MingCute-refresh_1",
        "arrow.up": "MingCute-arrow_up",
        "arrow.up.right": "MingCute-arrow_right_up",
        "arrow.up.forward.app": "MingCute-external_link",
        "arrow.down.to.line": "MingCute-download",
        "arrow.left.arrow.right": "MingCute-transfer",
        "arrow.turn.down.left": "MingCute-corner_down_left",
        "line.3.horizontal.decrease": "MingCute-filter_2",
        "list.bullet": "MingCute-history",
        "line.2.horizontal": "MingCute-custom-menu-2-lines",
        "pencil": "MingCute-edit",
        "paperclip": "MingCute-attachment",
        "stop.fill": "MingCute-filled-stop",
        "photo": "MingCute-pic",
        "text.document": "MingCute-document_2",
        "textformat": "MingCute-text",
        "doc": "MingCute-file",
        "doc.on.clipboard": "MingCute-clipboard",
        "note.text": "MingCute-notebook",
        "folder": "MingCute-folder",
        "link": "MingCute-link",
        "globe": "MingCute-earth",
        "brain": "MingCute-brain",
        "sparkles": "MingCute-sparkles",
        "calendar": "MingCute-calendar",
        "message": "MingCute-message_1",
        "bubble.left": "MingCute-chat_2",
        "text.bubble": "MingCute-chat_1",
        "terminal": "MingCute-terminal",
        "map": "MingCute-map",
        "car.fill": "MingCute-filled-car",
        "person.crop.circle": "MingCute-user_4",
        "person.crop.rectangle": "MingCute-contacts",
        "square.stack.3d.up": "MingCute-layers",
        "puzzlepiece.extension": "MingCute-plugin_2",
        "gearshape": "MingCute-settings_3",
        "gearshape.2": "MingCute-settings_6",
        "keyboard": "MingCute-keyboard",
        "command": "MingCute-command",
        "cursor_3": "MingCute-cursor_3",
        "command.square": "MingCute-command",
        "hand.raised.fill": "MingCute-filled-hand",
        "hand.draw": "MingCute-hand_finger",
        "info.circle": "MingCute-information",
        "star": "MingCute-star",
        "star.fill": "MingCute-filled-star",
        "app.badge": "MingCute-classify_add_2",
        "equal.square": "MingCute-counter_2",
        "dollarsign.arrow.circlepath": "MingCute-exchange_dollar",
        "record.circle": "MingCute-dot_circle",
        "accessibility": "MingCute-wheelchair",
        "bell.badge": "MingCute-notification_newdot",
        "externaldrive.badge.checkmark": "MingCute-storage",
        "bookmark": "MingCute-bookmark",
        "warning": "MingCute-warning",
        "tool": "MingCute-tool",
        "video": "MingCute-video",
        "power": "MingCute-power",
        "web": "MingCute-web",
        "layout_4_line": "MingCute-layout_4",
        "eyedropper": "MingCute-color_picker",
    ]

    static func image(_ symbol: String, size: CGFloat = 16, canvas: CGFloat? = nil) -> NSImage {
        guard let asset = assets[symbol], let image = NSImage(named: asset)?.copy() as? NSImage else {
            preconditionFailure("Missing MingCute icon: \(symbol)")
        }
        image.size = NSSize(width: size, height: size)
        image.isTemplate = true
        guard let canvas, canvas > size else { return image }
        // Menus size their clickable label to the image itself, so a padded canvas is what
        // gives the glyph a full-size hit area instead of only the strokes.
        let inset = (canvas - size) / 2
        let boxed = NSImage(size: NSSize(width: canvas, height: canvas), flipped: false) { _ in
            image.draw(in: NSRect(x: inset, y: inset, width: size, height: size))
            return true
        }
        boxed.isTemplate = true
        return boxed
    }
}

extension Image {
    init(mingCute symbol: String, size: CGFloat = 16) {
        self.init(nsImage: MingCute.image(symbol, size: size))
        self = self.renderingMode(.template)
    }
}
