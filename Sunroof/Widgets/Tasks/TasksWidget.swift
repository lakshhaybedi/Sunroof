import SwiftUI

struct TasksWidget: View {
    @Bindable var model: TasksModel
    let size: WidgetSize
    @State private var draft = ""
    @State private var justDone: Set<String> = []
    @FocusState private var adding: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            let visible = model.tasks.filter { !$0.done || justDone.contains($0.id) }
            if visible.isEmpty {
                Text("All done 🎉").font(.caption).foregroundStyle(.secondary).padding(.top, 4)
            }
            ForEach(visible.prefix(size == .large ? 9 : 3)) { row($0) }
            Spacer(minLength: 0)
            TextField("Add a task", text: $draft)
                .textFieldStyle(.plain).font(.caption)
                .focused($adding)
                .onSubmit { model.add(draft); draft = "" }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(spacing: 4) {
            Menu {
                Button("Sunroof (Tasks note)") { model.select(TasksModel.sunroofListID) }
                if model.remindersAllowed {
                    Divider()
                    ForEach(model.lists) { list in Button(list.title) { model.select(list.id) } }
                } else {
                    Divider()
                    Button(model.remindersAsked ? "Allow Reminders in Privacy Settings…" : "Use Apple Reminders…") {
                        if model.remindersAsked {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders")!)
                        } else { model.requestRemindersAccess() }
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Text(model.currentListTitle).font(.caption.bold())
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                }
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            Spacer()
            Text("\(model.tasks.filter { !$0.done }.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
    }

    private func row(_ task: TaskItem) -> some View {
        let done = task.done || justDone.contains(task.id)
        let overdue = !done && (task.due.map { $0 < Calendar.current.startOfDay(for: .now) } ?? false)
        return HStack(spacing: 6) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { justDone.insert(task.id) }
                model.toggle(task)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { withAnimation { _ = justDone.remove(task.id) } }
            } label: {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(done ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            }
            .buttonStyle(HitButtonStyle(minSize: 20))
            Text(task.title).font(.caption).lineLimit(1)
                .strikethrough(done).foregroundStyle(done ? .secondary : .primary)
            Spacer(minLength: 0)
            if let due = task.due {
                Text(due.formatted(.dateTime.day().month(.abbreviated))).font(.caption2)
                    .foregroundStyle(overdue ? .red : .secondary)
            }
        }
        .opacity(done ? 0.6 : 1)
    }
}
