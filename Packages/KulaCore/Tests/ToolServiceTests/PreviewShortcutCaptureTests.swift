import CoreGraphics
import Testing
@testable import ToolService

@MainActor
struct PreviewShortcutCaptureTests {
    @Test func neverReenablesOnUserInputDisable() {
        #expect(!PreviewShortcutCapture.shouldReenable(after: .tapDisabledByUserInput, desiredEnabled: false))
        #expect(!PreviewShortcutCapture.shouldReenable(after: .tapDisabledByUserInput, desiredEnabled: true))
    }

    @Test func reenablesOnTimeoutOnlyWhenDesiredEnabled() {
        #expect(!PreviewShortcutCapture.shouldReenable(after: .tapDisabledByTimeout, desiredEnabled: false))
        #expect(PreviewShortcutCapture.shouldReenable(after: .tapDisabledByTimeout, desiredEnabled: true))
    }
}
