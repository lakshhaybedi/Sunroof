import EventKit
import Foundation
import Testing
@testable import Sunroof

@MainActor @Suite struct TasksModelTests {
    @Test func backgroundReminderCompletionPublishesOnMainActor() async {
        let items: [TaskItem] = await withCheckedContinuation { continuation in
            let completion = TasksModel.remindersCompletion { items in
                MainActor.assertIsolated()
                continuation.resume(returning: items)
            }
            DispatchQueue.global().async {
                dispatchPrecondition(condition: .notOnQueue(.main))
                let store = EKEventStore()
                let later = EKReminder(eventStore: store)
                later.title = "Later"
                later.dueDateComponents = DateComponents(year: 2030, month: 6, day: 2)
                let earlier = EKReminder(eventStore: store)
                earlier.title = "Earlier"
                earlier.dueDateComponents = DateComponents(year: 2030, month: 6, day: 1)
                let undated = EKReminder(eventStore: store)
                undated.title = "Undated"
                completion([undated, later, earlier])
            }
        }
        #expect(items.map(\.title) == ["Earlier", "Later", "Undated"])
        #expect(items.allSatisfy { !$0.done })
        #expect(items[0].due != nil)
        #expect(items[2].due == nil)
    }

    @Test func nilBackgroundReminderResultsPublishEmptyList() async {
        let items: [TaskItem] = await withCheckedContinuation { continuation in
            let completion = TasksModel.remindersCompletion { items in
                MainActor.assertIsolated()
                continuation.resume(returning: items)
            }
            DispatchQueue.global().async { completion(nil) }
        }
        #expect(items.isEmpty)
    }
}
