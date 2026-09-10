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

        let targets: [PinboardColorToken: (hue: CGFloat, saturation: CGFloat, brightness: CGFloat)] = [
            .amber: (0.08, 0.90, 0.95),
            .green: (0.36, 0.80, 0.78),
            .cyan: (0.52, 0.89, 0.85),
            .blue: (0.60, 0.85, 0.92),
            .violet: (0.74, 0.70, 0.85),
            .pink: (0.93, 0.72, 0.97),
        ]

        for token in PinboardColorToken.allCases {
            let components = token.color.hsbComponents
            let target = try #require(targets[token])
            #expect(abs(components.hue - target.hue) < 0.01)
            #expect(abs(components.saturation - target.saturation) < 0.01)
            #expect(abs(components.brightness - target.brightness) < 0.01)
            #expect(components.saturation >= 0.55)
            #expect(components.brightness >= 0.75)
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

    @Test func deletionRemovesPinboardPersistsAndRejectsMissingNames() throws {
        let defaults = temporaryDefaults()
        let settings = AppSettings(defaults: defaults)
        let research = try #require(settings.createCustomPinboard(name: "Research", color: .violet))
        let personal = try #require(settings.createCustomPinboard(name: "Personal", color: .pink))

        #expect(settings.deleteCustomPinboard(named: " Research "))
        #expect(!settings.deleteCustomPinboard(named: "Missing"))
        #expect(settings.customPinboards.contains(personal))
        #expect(!settings.customPinboards.contains(research))

        let relaunched = AppSettings(defaults: defaults)
        #expect(relaunched.customPinboards.contains(personal))
        #expect(!relaunched.customPinboards.contains(research))
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

    @Test func updateCustomPinboardRenamesRecolorsAndPersists() throws {
        let defaults = temporaryDefaults()
        defaults.set("", forKey: "pinboardsText")
        let settings = AppSettings(defaults: defaults)
        let work = try #require(settings.createCustomPinboard(name: "Work", color: .amber))
        let ideas = try #require(settings.createCustomPinboard(name: "Ideas", color: .green))

        #expect(settings.updateCustomPinboard(named: "Work", newName: "  Project  ", color: .amber))
        #expect(settings.customPinboards == [
            CustomPinboard(name: "Project", color: .amber),
            CustomPinboard(name: "Ideas", color: .green)
        ])

        #expect(settings.updateCustomPinboard(named: "Project", newName: "Project", color: .blue))
        #expect(settings.customPinboards.first?.color == .blue)

        #expect(settings.updateCustomPinboard(named: "Project", newName: "Roadmap", color: .pink))
        #expect(settings.customPinboards.first == CustomPinboard(name: "Roadmap", color: .pink))
        #expect(!settings.customPinboards.contains(work))

        let relaunched = AppSettings(defaults: defaults)
        #expect(relaunched.customPinboards == [
            CustomPinboard(name: "Roadmap", color: .pink),
            CustomPinboard(name: "Ideas", color: .green)
        ])
    }

    @Test func updateCustomPinboardRejectsInvalidNamesAndMissingPinboards() throws {
        let defaults = temporaryDefaults()
        defaults.set("", forKey: "pinboardsText")
        let settings = AppSettings(defaults: defaults)
        let work = try #require(settings.createCustomPinboard(name: "Work", color: .amber))
        _ = try #require(settings.createCustomPinboard(name: "Ideas", color: .green))

        #expect(!settings.updateCustomPinboard(named: "Work", newName: "   ", color: .blue))
        #expect(!settings.updateCustomPinboard(named: "Work", newName: "Ideas", color: .blue))
        #expect(!settings.updateCustomPinboard(named: "  Ideas  ", newName: "Work", color: .blue))
        #expect(!settings.updateCustomPinboard(named: "Missing", newName: "Whatever", color: .blue))

        #expect(settings.updateCustomPinboard(named: "Work", newName: "Work", color: .blue))
        #expect(settings.customPinboards.contains(CustomPinboard(name: "Work", color: .blue)))
        #expect(settings.customPinboards.contains(CustomPinboard(name: "Ideas", color: .green)))
    }

    @Test func updateCustomPinboardValidationMatchesCreationSemantics() throws {
        let defaults = temporaryDefaults()
        defaults.set("", forKey: "pinboardsText")
        let settings = AppSettings(defaults: defaults)
        _ = try #require(settings.createCustomPinboard(name: "Work", color: .amber))
        _ = try #require(settings.createCustomPinboard(name: "Ideas", color: .green))

        #expect(settings.updateCustomPinboard(named: "Work", newName: "work", color: .amber))
        #expect(settings.customPinboards.contains(CustomPinboard(name: "work", color: .amber)))
        #expect(settings.customPinboards.contains(CustomPinboard(name: "Ideas", color: .green)))

        #expect(!settings.updateCustomPinboard(named: "work", newName: "Ideas", color: .amber))
        #expect(!settings.updateCustomPinboard(named: "work", newName: "  ", color: .amber))
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
