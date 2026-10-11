import Foundation
import Testing
@testable import Sunroof

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

    // Review I9: a folder whose contents are still being edited is not old.
    @Test func folderWithRecentContentsKept() {
        let folder = DrawerItem(url: URL(fileURLWithPath: "/d/Project"), name: "Project", isDirectory: true, kind: "",
                                dateAdded: now.addingTimeInterval(-40 * 86_400), dateModified: now.addingTimeInterval(-40 * 86_400), size: nil)
        let urls = Cleanup.itemsToClean([folder], olderThanDays: 30, now: now) { _ in now.addingTimeInterval(-86_400) }
        #expect(urls.isEmpty)
    }

    // Review I9: missing dates (exFAT, SMB, some cloud folders) count as "now", never as ancient.
    @Test func missingDatesCountAsNow() {
        #expect(DrawerItem.date(nil, now: now) == now)
    }

    @Test func offCleansNothing() {
        #expect(Cleanup.itemsToClean([item("old", addedDaysAgo: 400, modifiedDaysAgo: 400)], olderThanDays: 0, now: now).isEmpty)
    }
}
