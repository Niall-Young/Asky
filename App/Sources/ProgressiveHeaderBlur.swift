import AppKit
import SwiftUI

/// A tint-free backdrop whose grayscale mask controls blur radius, not opacity.
struct ProgressiveHeaderBlur: NSViewRepresentable {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func makeNSView(context: Context) -> ProgressiveHeaderBlurView { ProgressiveHeaderBlurView() }
    func updateNSView(_ view: ProgressiveHeaderBlurView, context: Context) {
        view.isHidden = reduceTransparency
    }
}

final class ProgressiveHeaderBlurView: NSView {
    private var backdrop: CALayer?
    private var lastSize: CGSize = .zero

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        // Resolve compositor classes dynamically so unsupported systems can omit
        // the decoration without changing transcript rendering or interactions.
        if let type = NSClassFromString("CABackdropLayer") as? CALayer.Type {
            let backdrop = type.init()
            backdrop.masksToBounds = true
            layer?.addSublayer(backdrop)
            self.backdrop = backdrop
        }
    }
    required init?(coder: NSCoder) { nil }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        guard bounds.size != lastSize, bounds.width > 0, bounds.height > 0 else { return }
        lastSize = bounds.size
        guard let backdrop,
              let filterType = NSClassFromString("CAFilter") as? NSObject.Type,
              filterType.responds(to: NSSelectorFromString("filterWithType:")),
              let filter = filterType.perform(NSSelectorFromString("filterWithType:"), with: "variableBlur")?.takeUnretainedValue() as? NSObject,
              let context = CGContext(data: nil, width: 1, height: 256, bitsPerComponent: 8,
                                      bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: [NSColor.clear.cgColor, NSColor.white.cgColor] as CFArray,
                                        locations: [0, 1]) else { return }
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: 256), options: [])
        guard let mask = context.makeImage() else { return }
        filter.setValue(18.0, forKey: "inputRadius")
        filter.setValue(mask, forKey: "inputMaskImage")
        filter.setValue(true, forKey: "inputNormalizeEdges")
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backdrop.frame = bounds
        backdrop.filters = [filter]
        CATransaction.commit()
    }
}
