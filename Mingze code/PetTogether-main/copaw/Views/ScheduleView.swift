import SwiftUI

struct ScheduleView: View {
    @EnvironmentObject private var store: CareStore
    @EnvironmentObject private var language: AppLanguageStore
    @State private var selectedDate = Date()
    @State private var filter = ScheduleFilter.all
    @State private var isAddingTask = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        ZStack {
            PetScreenBackground()

            ScrollView {
                LazyVStack(spacing: 18) {
                    calendarCard
                    filterBar
                    agenda
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
        }
        .navigationTitle(L10n.text(language.language, "Calendar", "カレンダー"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    isAddingTask = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.pawPurple, in: Circle())
                }
                .accessibilityLabel("Add task on selected date")
            }
        }
        .sheet(isPresented: $isAddingTask) {
            AddTaskView(
                initialDate: selectedDate,
                timeZoneIdentifier: store.household?.timeZoneIdentifier ?? TimeZone.current.identifier
            )
        }
    }

    private var calendarCard: some View {
        VStack(spacing: 15) {
            HStack {
                Button {
                    moveMonth(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Previous month")

                Spacer()
                VStack(spacing: 2) {
                    Text(formatted(selectedDate, pattern: "LLLL yyyy"))
                        .font(.title3.bold())
                        .foregroundStyle(Color.pawInk)
                    Text("Routine and extra care together")
                        .font(.caption2)
                        .foregroundStyle(Color.pawMuted)
                }
                Spacer()

                Button {
                    moveMonth(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Next month")
            }
            .foregroundStyle(Color.pawPurple)

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption2.bold())
                        .foregroundStyle(Color.pawMuted)
                        .frame(maxWidth: .infinity)
                }

                ForEach(Array(monthDays.enumerated()), id: \.offset) { _, date in
                    if let date {
                        CalendarDayCell(
                            date: date,
                            isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                            isToday: calendar.isDateInToday(date),
                            tasks: store.tasks(on: date),
                            calendar: calendar
                        ) {
                            selectedDate = date
                        }
                    } else {
                        Color.clear.frame(height: 48)
                    }
                }
            }

            HStack(spacing: 14) {
                legend("Routine", icon: "arrow.triangle.2.circlepath", color: .pawPurple)
                legend("One-time", icon: "circle.fill", color: .pawBlue)
                legend("Urgent", icon: "exclamationmark.circle.fill", color: .pawRose)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .petCard(padding: 15)
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            ForEach(ScheduleFilter.allCases) { item in
                Button(item.title) {
                    filter = item
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(filter == item ? .white : Color.pawPurple)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .background(
                    filter == item ? Color.pawPurple : Color.white.opacity(0.9),
                    in: Capsule()
                )
                .buttonStyle(.plain)
                .accessibilityAddTraits(filter == item ? .isSelected : [])
            }
        }
    }

    private var agenda: some View {
        VStack(alignment: .leading, spacing: 14) {
            PetSectionTitle(
                title: formatted(selectedDate, pattern: "EEEE, MMM d"),
                detail: "\(filteredTasks.count) TASK\(filteredTasks.count == 1 ? "" : "S")"
            )

            if filteredTasks.isEmpty {
                VStack(spacing: 10) {
                    CareIcon(systemName: "calendar.badge.plus", color: .pawPurple, size: 56)
                    Text("No care planned yet")
                        .font(.headline)
                        .foregroundStyle(Color.pawInk)
                    Text("Add a one-time need or start a daily routine for this date.")
                        .font(.subheadline)
                        .foregroundStyle(Color.pawMuted)
                        .multilineTextAlignment(.center)
                    Button("Add care") { isAddingTask = true }
                        .font(.subheadline.bold())
                        .foregroundStyle(Color.pawPurple)
                        .frame(minHeight: 44)
                }
                .frame(maxWidth: .infinity)
                .petCard()
            } else {
                if filter != .oneOff, !routineTasks.isEmpty {
                    taskGroup(
                        title: "Daily routine",
                        detail: "REPEATS",
                        tasks: routineTasks
                    )
                }

                if filter != .routine, !oneOffTasks.isEmpty {
                    taskGroup(
                        title: "Extra care",
                        detail: oneOffTasks.contains(where: { $0.priority == .urgent }) ? "URGENT INCLUDED" : "ONE-TIME",
                        tasks: oneOffTasks
                    )
                }
            }
        }
    }

    private func taskGroup(title: String, detail: String, tasks: [CareTask]) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            PetSectionTitle(title: title, detail: detail)
            ForEach(tasks) { task in
                TaskCardView(task: task)
            }
        }
    }

    private func legend(_ title: String, icon: String, color: Color) -> some View {
        Label(title, systemImage: icon)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
    }

    private var filteredTasks: [CareTask] {
        switch filter {
        case .all: store.tasks(on: selectedDate)
        case .routine: routineTasks
        case .oneOff: oneOffTasks
        }
    }

    private var routineTasks: [CareTask] {
        store.tasks(on: selectedDate).filter { $0.kind == .routine }
    }

    private var oneOffTasks: [CareTask] {
        store.tasks(on: selectedDate).filter { $0.kind == .oneOff }
    }

    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: store.household?.timeZoneIdentifier ?? "") ?? .current
        value.firstWeekday = 1
        return value
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let offset = max(calendar.firstWeekday - 1, 0)
        return Array(symbols[offset...] + symbols[..<offset])
    }

    private var monthDays: [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: selectedDate),
              let dayRange = calendar.range(of: .day, in: .month, for: selectedDate) else {
            return []
        }
        let weekday = calendar.component(.weekday, from: interval.start)
        let leading = (weekday - calendar.firstWeekday + 7) % 7
        let dates = dayRange.compactMap {
            calendar.date(byAdding: .day, value: $0 - 1, to: interval.start)
        }
        return Array(repeating: nil, count: leading) + dates.map(Optional.some)
    }

    private func moveMonth(by value: Int) {
        if let date = calendar.date(byAdding: .month, value: value, to: selectedDate) {
            selectedDate = date
        }
    }

    private func formatted(_ date: Date, pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}

private enum ScheduleFilter: String, CaseIterable, Identifiable {
    case all
    case routine
    case oneOff

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .routine: "Routine"
        case .oneOff: "One-time"
        }
    }
}

private struct CalendarDayCell: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let tasks: [CareTask]
    let calendar: Calendar
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(spacing: 4) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.subheadline.weight(isSelected ? .bold : .medium))
                    .foregroundStyle(isSelected ? .white : Color.pawInk)

                HStack(spacing: 3) {
                    if tasks.contains(where: { $0.kind == .routine }) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 7, weight: .bold))
                    }
                    if tasks.contains(where: { $0.kind == .oneOff }) {
                        Circle().frame(width: 5, height: 5)
                    }
                    if tasks.contains(where: { $0.priority == .urgent }) {
                        Image(systemName: "exclamationmark")
                            .font(.system(size: 8, weight: .black))
                    }
                }
                .foregroundStyle(isSelected ? Color.white : indicatorColor)
                .frame(height: 8)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(
                isSelected ? Color.pawPurple : Color.clear,
                in: RoundedRectangle(cornerRadius: 14)
            )
            .overlay {
                if isToday && !isSelected {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.pawPurple.opacity(0.55), lineWidth: 1.5)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var indicatorColor: Color {
        tasks.contains(where: { $0.priority == .urgent }) ? .pawRose : .pawPurple
    }

    private var accessibilityText: String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        let dateText = formatter.string(from: date)
        guard !tasks.isEmpty else { return dateText }

        var details: [String] = []
        if tasks.contains(where: { $0.kind == .routine }) {
            details.append("routine")
        }
        if tasks.contains(where: { $0.kind == .oneOff }) {
            details.append("one-time")
        }
        if tasks.contains(where: { $0.priority == .urgent }) {
            details.append("urgent")
        }
        let taskLabel = tasks.count == 1 ? "care task" : "care tasks"
        return "\(dateText), \(tasks.count) \(taskLabel), \(details.joined(separator: ", "))"
    }
}
