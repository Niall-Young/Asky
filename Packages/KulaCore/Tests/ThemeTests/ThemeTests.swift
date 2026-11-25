import Testing
@testable import Theme

@Suite struct ThemeTests {
    @Test func everySemanticColorResolvesInBothModes() {
        for name in SemanticColors.sourceTable.keys {
            for mode in Appearance.allCases {
                #expect(SemanticColors.resolve(name, mode) != nil, "\(name) \(mode)")
            }
        }
    }

    @Test func everyNativeNameMapsToASource() {
        for native in SemanticColors.nativeToSource.keys {
            #expect(SemanticColors.color(native: native, .light) != nil, "\(native)")
        }
    }

    @Test func paletteAlphaFollowsStep() {
        #expect(Palette.values["black90"]?.alpha == 0.9)
        #expect(Palette.values["white0"]?.alpha == 0)
    }

    @Test func capsuleRadius() {
        #expect(Radius.isCapsule("radius99999"))
        #expect(!Radius.isCapsule("radius8"))
    }

    @Test func warningAndNegativeTokensUseAppearanceAdaptivePalette() {
        #expect(SemanticColors.color(native: "textWarning", .light) == RGBA(hex: 0xAD690B, alpha: 1))
        #expect(SemanticColors.color(native: "textWarning", .dark) == RGBA(hex: 0xE8AD52, alpha: 1))

        let lightRed = RGBA(hex: 0xB84542, alpha: 1)
        let darkRedText = RGBA(hex: 0xDC726E, alpha: 1)
        let darkRedFill = RGBA(hex: 0xB54B48, alpha: 1)
        for token in ["textNegative", "iconNegative", "borderNegative"] {
            #expect(SemanticColors.color(native: token, .light) == lightRed, "\(token) light")
            #expect(SemanticColors.color(native: token, .dark) == darkRedText, "\(token) dark")
        }
        #expect(SemanticColors.color(native: "backgroundNegative", .light) == lightRed)
        #expect(SemanticColors.color(native: "backgroundNegative", .dark) == darkRedFill)
    }
}
