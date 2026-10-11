import ApplicationServices

enum Permissions {
    static var isAccessibilityTrusted: Bool { AXIsProcessTrusted() }

    static func requestAccessibility() {
        let key = "AXTrustedCheckOptionPrompt" // kAXTrustedCheckOptionPrompt, as a literal for Swift 6 concurrency
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }
}
