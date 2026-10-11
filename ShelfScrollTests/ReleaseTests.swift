import Foundation
import Testing
@testable import ShelfScroll

@Suite struct ReleaseTests {
    func info(_ key: String) -> Any? { Bundle.main.object(forInfoDictionaryKey: key) }

    @Test func feedURLConfigured() {
        #expect(info("SUFeedURL") as? String == "https://lakshhaybedi.github.io/ShelfScroll/appcast.xml")
    }

    @Test func automaticChecksOn() {
        #expect(info("SUEnableAutomaticChecks") as? Bool == true)
    }

    @Test func versionIsSemver() {
        let v = info("CFBundleShortVersionString") as? String ?? ""
        #expect(v.range(of: #"^\d+\.\d+\.\d+$"#, options: .regularExpression) != nil)
    }

    @Test func hasAppIcon() {
        #expect(info("CFBundleIconName") as? String == "AppIcon")
    }
}
