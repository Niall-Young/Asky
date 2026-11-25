import AppKit
import SwiftUI
import ToolService

extension View {
    func appDialog(_ title: String, isPresented: Binding<Bool>, message: String,
                   buttons: [String], destructive: Bool = false,
                   onResponse: @escaping (Int) -> Void = { _ in }) -> some View {
        modifier(AppDialogModifier(title: title, isPresented: isPresented,
                                   message: message, buttons: buttons,
                                   destructive: destructive, onResponse: onResponse))
    }
}

private struct AppDialogModifier: ViewModifier {
    let title: String
    @Binding var isPresented: Bool
    let message: String
    let buttons: [String]
    let destructive: Bool
    let onResponse: (Int) -> Void
    @State private var anchorBox = AppDialogWeakViewBox()

    func body(content: Content) -> some View {
        content
            .background(AppDialogViewReader(box: anchorBox).allowsHitTesting(false))
            .onChange(of: isPresented) { _, presented in
                guard presented else { return }
                Task { @MainActor in
                    guard isPresented else { return }
                    let alert = AppDialog.make()
                    alert.messageText = title
                    alert.informativeText = message
                    for (index, buttonTitle) in buttons.enumerated() {
                        let button = alert.addButton(withTitle: buttonTitle)
                        if index == 0 {
                            button.keyEquivalent = "\r"
                            if destructive { button.hasDestructiveAction = true }
                        } else if index == buttons.count - 1 {
                            button.keyEquivalent = "\u{1b}"
                        }
                    }
                    NSApp.activate()
                    let response = await AppDialog.present(alert, for: anchorBox.view?.window)
                    isPresented = false
                    onResponse(response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue)
                }
            }
    }
}
