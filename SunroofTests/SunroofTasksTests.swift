import Foundation
import Testing
@testable import Sunroof

@Suite struct SunroofTasksTests {
    let text = "Tasks\n\nSome intro\n- [ ] Buy milk\n- [x] Call mum\n* [ ] Book flights\n- not a task"

    @Test func parsesOnlyCheckboxLines() {
        let tasks = SunroofTasks.parse(text)
        #expect(tasks.map(\.title) == ["Buy milk", "Call mum", "Book flights"])
        #expect(tasks.map(\.done) == [false, true, false])
    }

    // Review Focus 5: ticking touches only the target line.
    @Test func togglingChangesOneLine() {
        let milk = SunroofTasks.parse(text)[0]
        let after = SunroofTasks.toggling(milk.id, in: text)
        #expect(after == text.replacingOccurrences(of: "- [ ] Buy milk", with: "- [x] Buy milk"))
    }

    @Test func addingAppendsUnderTheLastTask() {
        #expect(SunroofTasks.adding("Water plants", to: text) ==
                "Tasks\n\nSome intro\n- [ ] Buy milk\n- [x] Call mum\n* [ ] Book flights\n- [ ] Water plants\n- not a task")
    }

    @Test func addingToEmptyCreatesTheNote() {
        #expect(SunroofTasks.adding("First", to: "") == "Tasks\n\n- [ ] First")
        #expect(SunroofTasks.adding("First", to: "Tasks") == "Tasks\n\n- [ ] First")
    }

    @Test func emptyTitlesIgnored() {
        #expect(SunroofTasks.adding("   ", to: text) == text)
    }

    @Test func externalEditIsReflected() async throws {
        let folder = tempDir().appendingPathComponent("Notes")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = await NoteStore(folder: folder)
        let model = await SunroofTasksSource(store: store)
        await model.add("One")
        #expect(await model.tasks.map(\.title) == ["One"])
        await store.update("Tasks.md", text: "Tasks\n\n- [ ] One\n- [ ] Two from another Mac")
        #expect(await model.tasks.map(\.title) == ["One", "Two from another Mac"])
    }
}
