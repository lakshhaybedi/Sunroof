import Testing
@testable import Sunroof

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

    // Feedback: drag a column's header onto another column to move it there.
    @Test func movingPanels() {
        let order: [PanelID] = [.clipboard, .files, .notes]
        #expect(movingPanel(.clipboard, onto: .notes, in: order) == [.files, .notes, .clipboard])
        #expect(movingPanel(.notes, onto: .clipboard, in: order) == [.notes, .clipboard, .files])
        #expect(movingPanel(.files, onto: .notes, in: order) == [.clipboard, .notes, .files])
        #expect(movingPanel(.files, onto: .files, in: order) == order)
    }
}
