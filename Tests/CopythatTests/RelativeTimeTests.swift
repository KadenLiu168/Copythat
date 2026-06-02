@testable import Copythat
import Foundation
import Testing

struct RelativeTimeTests {
    @Test func relativeTimeUsesStableEnglishLabels() {
        #expect(RelativeTime.string(from: Date().addingTimeInterval(-10)) == "just now")
        #expect(RelativeTime.string(from: Date().addingTimeInterval(-60)).contains("minute ago"))
        #expect(RelativeTime.string(from: Date().addingTimeInterval(-120)).contains("minutes ago"))
        #expect(RelativeTime.string(from: Date().addingTimeInterval(-3_600)).contains("hour ago"))
        #expect(RelativeTime.string(from: Date().addingTimeInterval(-7_200)).contains("hours ago"))
    }
}
