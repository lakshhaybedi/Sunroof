import SwiftUI

struct CalendarWidget: View {
    @Bindable var model: CalendarModel
    let size: WidgetSize
    @Environment(AppSettings.self) private var settings

    var body: some View {
        Group {
            switch model.access {
            case .granted:
                if size == .medium && settings.calendarMediumShowsAgenda { upcoming } else { month }
            case .unknown:
                AccessPrompt(symbol: "calendar", text: "See your calendar here", button: "Allow Calendar Access") { model.requestAccess() }
            case .denied:
                AccessPrompt(symbol: "calendar.badge.exclamationmark", text: "Calendar access is off", button: "Open Privacy Settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
                }
            }
        }
        .padding(size == .large ? 12 : 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Month

    private var compact: Bool { size == .medium }

    private var month: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: compact ? 2 : 4) {
                header
                let initials = MonthGrid.weekdayInitials(firstWeekday: model.calendar.firstWeekday, calendar: model.calendar)
                HStack(spacing: 0) {
                    ForEach(Array(initials.enumerated()), id: \.offset) { _, s in
                        Text(s).font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                    }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: compact ? 1 : 2) {
                    ForEach(visibleDays) { day in dayCell(day) }
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 6) { if size == .large { agenda } }
    }

    /// Compact: only weeks that contain days of this month (5 or 6 rows) so it fits a medium tile.
    private var visibleDays: [MonthGrid.Day] {
        guard compact else { return model.grid }
        let weeks = stride(from: 0, to: model.grid.count, by: 7).map { Array(model.grid[$0..<$0 + 7]) }
        return weeks.filter { $0.contains(where: \.inMonth) }.flatMap { $0 }
    }

    private var header: some View {
        HStack(spacing: 4) {
            Text(model.month.formatted(.dateTime.month(.wide).year())).font(compact ? .caption.bold() : .callout.bold())
            Spacer()
            if compact {
                Button { settings.calendarMediumShowsAgenda = true } label: { Image(systemName: "list.bullet") }
                    .buttonStyle(HitButtonStyle(minSize: 20)).help("Show upcoming events")
            }
            Button { model.shiftMonth(-1) } label: { Image(systemName: "chevron.left") }.buttonStyle(HitButtonStyle(minSize: 20))
            Button { model.goToToday() } label: { Image(systemName: "circle.fill").font(.system(size: 5)) }
                .buttonStyle(HitButtonStyle(minSize: 20)).help("Today")
            Button { model.shiftMonth(1) } label: { Image(systemName: "chevron.right") }.buttonStyle(HitButtonStyle(minSize: 20))
        }
        .foregroundStyle(.primary)
    }

    private func dayCell(_ day: MonthGrid.Day) -> some View {
        let events = model.eventsByDay[day.date] ?? []
        let selected = model.calendar.isDate(day.date, inSameDayAs: model.selectedDay)
        return Button { model.selectedDay = day.date } label: {
            VStack(spacing: 1) {
                Text("\(model.calendar.component(.day, from: day.date))")
                    .font(.system(size: compact ? 9 : 11, weight: day.isToday ? .bold : .regular).monospacedDigit())
                    .foregroundStyle(day.isToday ? AnyShapeStyle(.white) : day.inMonth ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                    .frame(width: compact ? 14 : 20, height: compact ? 14 : 20)
                    .background(Circle().fill(day.isToday ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear)))
                    .overlay(Circle().stroke(.tint, lineWidth: selected && !day.isToday ? 1.5 : 0))
                    .overlay(alignment: .trailing) { // compact: one dot beside the number, no extra row
                        if compact, !events.isEmpty { Circle().fill(.tint).frame(width: 3, height: 3).offset(x: 4) }
                    }
                if !compact {
                    HStack(spacing: 2) {
                        ForEach(Array(Set(events.map(\.color)).prefix(3).enumerated()), id: \.offset) { _, c in
                            Circle().fill(Color(nsColor: c)).frame(width: 4, height: 4)
                        }
                    }
                    .frame(height: 4)
                }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var agenda: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(model.selectedDay.formatted(.dateTime.weekday(.wide).day().month())).font(.caption.bold())
                Spacer()
                Button { model.openCalendarApp() } label: { Image(systemName: "plus") }
                    .buttonStyle(HitButtonStyle(minSize: 20)).help("New event in Calendar")
            }
            if model.selectedEvents.isEmpty {
                Text("No events").font(.caption).foregroundStyle(.secondary)
            }
            ForEach(model.selectedEvents.prefix(3)) { eventRow($0) }
            if model.selectedEvents.count > 3 {
                Text("+\(model.selectedEvents.count - 3) more").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func eventRow(_ e: CalendarModel.Event) -> some View {
        Button { model.openCalendarApp() } label: {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 1.5).fill(Color(nsColor: e.color)).frame(width: 3, height: 14)
                Text(e.allDay ? "All day" : e.start.formatted(date: .omitted, time: .shortened))
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary).frame(width: 52, alignment: .leading)
                Text(e.title).font(.caption).lineLimit(1)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Upcoming (medium, toggled)

    private var upcoming: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Upcoming").font(.caption.bold())
                Spacer()
                Button { settings.calendarMediumShowsAgenda = false } label: { Image(systemName: "calendar") }
                    .buttonStyle(HitButtonStyle(minSize: 20)).help("Show month")
            }
            let next = model.upcoming(3)
            if next.isEmpty { Text("Nothing coming up").font(.caption).foregroundStyle(.secondary) }
            ForEach(next) { e in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 1.5).fill(Color(nsColor: e.color)).frame(width: 3, height: 26)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(e.title).font(.caption).lineLimit(1)
                        Text(e.allDay ? e.start.formatted(.dateTime.weekday().day().month()) : e.start.formatted(.dateTime.weekday().hour().minute()))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

/// "Grant access" state shared by widgets that need a permission.
struct AccessPrompt: View {
    let symbol: String
    let text: String
    let button: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.title2).foregroundStyle(.tint)
            Text(text).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button(button, action: action).controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
