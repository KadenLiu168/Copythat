@testable import Copythat
import AppKit
import Foundation
import Testing

@MainActor
struct AppSettingsPinboardTests {
    @Test func colorTokensRoundTripAndShareSaturationAndBrightness() throws {
        let encoded = try JSONEncoder().encode(PinboardColorToken.allCases)
        let decoded = try JSONDecoder().decode([PinboardColorToken].self, from: encoded)

        #expect(decoded == PinboardColorToken.allCases)
        #expect(Set(PinboardColorToken.allCases.map { $0.color.hsbComponents.hue }).count == PinboardColorToken.allCases.count)
        for token in PinboardColorToken.allCases {
            let components = token.color.hsbComponents
            #expect(abs(components.saturation - 0.72) < 0.001)
            #expect(abs(components.brightness - 0.88) < 0.001)
        }
    }

    @Test func creationTrimsNamesPersistsColorsAndRejectsInvalidNames() throws {
        let defaults = temporaryDefaults()
        let settings = AppSettings(defaults: defaults)

        let created = try #require(settings.createCustomPinboard(name: "  Research  ", color: .violet))

        #expect(created == CustomPinboard(name: "Research", color: .violet))
        #expect(settings.createCustomPinboard(name: "   ", color: .blue) == nil)
        #expect(settings.createCustomPinboard(name: "Research", color: .pink) == nil)
        #expect(settings.createCustomPinboard(name: "Personal", color: .violet) != nil)

        let relaunched = AppSettings(defaults: defaults)
        #expect(relaunched.customPinboards.contains(created))
        #expect(relaunched.customPinboards.suffix(2).allSatisfy { $0.color == .violet })
    }

    @Test func legacyNamesMigrateInOrderWithoutEmptyOrDuplicateNames() {
        let defaults = temporaryDefaults()
        defaults.set(" Work \n\nIdeas\nWork\nPersonal ", forKey: "pinboardsText")

        let settings = AppSettings(defaults: defaults)

        #expect(settings.customPinboards == [
            CustomPinboard(name: "Work", color: .amber),
            CustomPinboard(name: "Ideas", color: .green),
            CustomPinboard(name: "Personal", color: .cyan)
        ])
        #expect(defaults.data(forKey: "customPinboards") != nil)
    }

    @Test func emptyLegacyListKeepsOnlyBuiltInPinboardsAvailable() {
        let defaults = temporaryDefaults()
        defaults.set("", forKey: "pinboardsText")

        let settings = AppSettings(defaults: defaults)

        #expect(settings.customPinboards.isEmpty)
    }

    private func temporaryDefaults() -> UserDefaults {
        let suiteName = "AppSettingsPinboardTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

private extension NSColor {
    var hsbComponents: (hue: CGFloat, saturation: CGFloat, brightness: CGFloat) {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: nil)
        return (hue, saturation, brightness)
    }
}
