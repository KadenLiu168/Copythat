@testable import Copythat
import AppKit
import Foundation
import Testing

@MainActor
struct AppSettingsPinboardTests {
    @Test func colorTokensRoundTripKeepDistinctHuesAndMeetRenderedVividnessFloors() throws {
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

            let unmet = unmetRenderedVividnessFloors(of: token.color)
            #expect(
                unmet.isEmpty,
                "\(token.rawValue) falls below rendered floors: \(unmet.map(\.rawValue).joined(separator: ", "))"
            )
        }
    }

    @Test func oklabConversionMatchesPublishedReferenceValues() {
        #expect(NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1).oklab.chroma < 0.001)
        #expect(NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1).oklab.chroma < 0.001)

        // Reference vector derived from this helper and confirmed against the
        // published OKLab definition: Ottosson's linear-sRGB -> LMS and cube-root
        // LMS -> OKLab constants, plus his XYZ example table (which an independent
        // XYZ-route implementation reproduces exactly). Not typed from memory.
        let red = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1).oklab
        #expect(abs(red.l - 0.627955) < 0.002)
        #expect(abs(red.a - 0.224863) < 0.002)
        #expect(abs(red.b - 0.125846) < 0.002)
    }

    @Test func paletteChromaMatchesAuditedBaseline() throws {
        // Chroma produced by the audit that motivated this change.
        let baseline: [PinboardColorToken: Double] = [
            .amber: 0.165,
            .green: 0.210,
            .cyan: 0.133,
            .blue: 0.174,
            .violet: 0.193,
            .pink: 0.196,
        ]

        for token in PinboardColorToken.allCases {
            let expected = try #require(baseline[token])
            #expect(abs(token.color.oklab.chroma - expected) < 0.002, "\(token.rawValue)")
        }
    }

    @Test func renderedVividnessFloorsRejectPreviouslyShippedUnderVividCyan() {
        // First-pass cyan shipped by increase-pinboard-color-saturation: calibrated
        // HSB 0.52 / 0.60 / 0.82. It passed the calibrated floors below, and the
        // entire suite, while rendering less colorful than the palette it replaced.
        let shipped = NSColor(calibratedHue: 0.52, saturation: 0.60, brightness: 0.82, alpha: 1)

        let calibrated = shipped.hsbComponents
        #expect(calibrated.saturation >= 0.55)
        #expect(calibrated.brightness >= 0.75)

        // The rendered floors reject it. It also misses the rendered saturation
        // floor (0.5497), plus the chroma floor (0.0993); only the chroma floor
        // isolates the failure, which the test below pins down.
        #expect(unmetRenderedVividnessFloors(of: shipped) == [.saturation, .chroma])
    }

    @Test func chromaFloorRejectsColorThatPassesRenderedSaturationAndBrightness() {
        // Calibrated 0.52 / 0.61 / 0.82 renders to sRGB saturation 0.5605 and
        // brightness 0.8547 — enough to clear both rendered-space HSB floors, so
        // only an OKLab chroma assertion can reject it. Without this case the
        // chroma floor could be deleted without any test noticing.
        let nearMiss = NSColor(calibratedHue: 0.52, saturation: 0.61, brightness: 0.82, alpha: 1)

        #expect(unmetRenderedVividnessFloors(of: nearMiss) == [.chroma])
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

    @Test func persistedPinboardEncoderUsesSortedKeys() {
        #expect(AppSettings.makeCustomPinboardsEncoder().outputFormatting.contains(.sortedKeys))
    }

    @Test func persistedPinboardPayloadIsCanonicalGolden() throws {
        let pinboards = [
            CustomPinboard(name: "Github", color: .green),
            CustomPinboard(name: "SKILL.md 优化", color: .pink)
        ]
        let data = try AppSettings.makeCustomPinboardsEncoder().encode(pinboards)
        // Golden payload generated from the encoder itself; keys are alphabetical
        // (color before name) because of .sortedKeys. Any field added to, removed
        // from, or reordered in this payload means the wire format changed.
        let golden = "[{\"color\":\"green\",\"name\":\"Github\"},{\"color\":\"pink\",\"name\":\"SKILL.md 优化\"}]"
        #expect(String(decoding: data, as: UTF8.self) == golden)
    }

    private func temporaryDefaults() -> UserDefaults {
        let suiteName = "AppSettingsPinboardTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}

// MARK: - Rendered vividness

/// A minimum-vividness floor, evaluated on the color the display receives.
private enum RenderedVividnessFloor: String, CaseIterable {
    case saturation
    case brightness
    case chroma

    var minimum: Double {
        switch self {
        case .saturation: 0.55
        case .brightness: 0.75
        case .chroma: 0.11
        }
    }

    func measured(in color: NSColor) -> Double {
        switch self {
        case .saturation: color.renderedSaturationAndBrightness.saturation
        case .brightness: color.renderedSaturationAndBrightness.brightness
        case .chroma: color.oklab.chroma
        }
    }

    func isMet(by color: NSColor) -> Bool {
        measured(in: color) >= minimum
    }
}

/// The rendered-space vividness assertion for one color. Empty means it passes.
private func unmetRenderedVividnessFloors(of color: NSColor) -> [RenderedVividnessFloor] {
    RenderedVividnessFloor.allCases.filter { !$0.isMet(by: color) }
}

// MARK: - Color measurement

/// OKLab coordinates, per Björn Ottosson's published definition.
private struct OKLab {
    let l: Double
    let a: Double
    let b: Double

    var chroma: Double { (a * a + b * b).squareRoot() }
}

private extension NSColor {
    var hsbComponents: (hue: CGFloat, saturation: CGFloat, brightness: CGFloat) {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: nil)
        return (hue, saturation, brightness)
    }

    /// Palette colors are declared in the calibrated space, which is not the space
    /// that reaches the display. Every floor is judged on this conversion, not on
    /// `hsbComponents`.
    var renderedSRGB: NSColor {
        usingColorSpace(.sRGB)!
    }

    var renderedSaturationAndBrightness: (saturation: Double, brightness: Double) {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        renderedSRGB.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: nil)
        return (Double(saturation), Double(brightness))
    }

    var oklab: OKLab {
        func linearized(_ component: CGFloat) -> Double {
            let value = Double(component)
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }

        let r = linearized(renderedSRGB.redComponent)
        let g = linearized(renderedSRGB.greenComponent)
        let b = linearized(renderedSRGB.blueComponent)

        // Published constants: linear sRGB -> LMS, then cube-root LMS -> OKLab.
        let l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
        let m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
        let s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b
        let lRoot = cbrt(l)
        let mRoot = cbrt(m)
        let sRoot = cbrt(s)

        return OKLab(
            l: 0.2104542553 * lRoot + 0.7936177850 * mRoot - 0.0040720468 * sRoot,
            a: 1.9779984951 * lRoot - 2.4285922050 * mRoot + 0.4505937099 * sRoot,
            b: 0.0259040371 * lRoot + 0.7827717662 * mRoot - 0.8086757660 * sRoot
        )
    }
}
