import Foundation
import Testing
@testable import ShelfScroll

@Suite struct CleanupTests {
    let now = Date(timeIntervalSince1970: 100 * 86_400)

    func item(_ name: String, addedDaysAgo a: Double, modifiedDaysAgo m: Double) -> DrawerItem {
        DrawerItem(url: URL(fileURLWithPath: "/d/\(name)"), name: name, isDirectory: false, kind: "",
                   dateAdded: now.addingTimeInterval(-a * 86_400), dateModified: now.addingTimeInterval(-m * 86_400), size: nil)
    }

    @Test func onlyWhenBothDatesOld() {
        let items = [item("old", addedDaysAgo: 40, modifiedDaysAgo: 40),
                     item("recentlyEdited", addedDaysAgo: 40, modifiedDaysAgo: 2),
                     item("recentlyAdded", addedDaysAgo: 2, modifiedDaysAgo: 40)]
        #expect(Cleanup.itemsToClean(items, olderThanDays: 30, now: now).map(\.lastPathComponent) == ["old"])
    }

    @Test func offCleansNothing() {
        #expect(Cleanup.itemsToClean([item("old", addedDaysAgo: 400, modifiedDaysAgo: 400)], olderThanDays: 0, now: now).isEmpty)
    }
}
