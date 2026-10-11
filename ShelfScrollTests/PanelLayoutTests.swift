import Testing
@testable import ShelfScroll

@Suite struct PanelLayoutTests {
    let all = Set(PanelID.allCases)

    @Test func defaultOrder() {
        #expect(visiblePanels(order: [.clipboard, .files, .notes], enabled: all) == [.clipboard, .files, .notes])
    }
    @Test func respectsEnabled() {
        #expect(visiblePanels(order: [.clipboard, .files, .notes], enabled: [.files]) == [.files])
    }
    @Test func customOrder() {
        #expect(visiblePanels(order: [.notes, .clipboard, .files], enabled: all) == [.notes, .clipboard, .files])
    }
    @Test func missingIDsAppended() {
        #expect(visiblePanels(order: [.notes], enabled: all) == [.notes, .clipboard, .files])
    }
    @Test func duplicatesRemoved() {
        #expect(visiblePanels(order: [.files, .files, .notes], enabled: all) == [.files, .notes, .clipboard])
    }
}
