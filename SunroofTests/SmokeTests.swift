import Foundation
import Testing
@testable import Sunroof

@Test func bundleIdentifier() {
    #expect(Bundle.main.bundleIdentifier == "com.lakshhaybedi.Sunroof")
}
