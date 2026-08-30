import SwiftUI

struct AddTaskView: View {
    @EnvironmentObject private var store: CareStore
    @EnvironmentObject private var language: AppLanguageStore
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var category = CareCategory.feeding
    @State private var kind = CareTaskKind.oneOff
    @State private var priority = CarePriority.normal
    @State private var weekdays = Array(1...7)
    @State private var dueDate: Date
    private let timeZoneIdentifier: String

    init(
        initialDate: Date = Date(),
        timeZoneIdentifier: String = TimeZone.current.identifier
    ) {
        self.timeZoneIdentifier = timeZoneIdentifier
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        let now = Date()
        var selected = calendar.dateComponents([.year, .month, .day], from: initialDate)
        let currentTime = calendar.dateComponents([.hour, .minute], from: now)
        selected.hour = currentTime.hour
        selected.minute = currentTime.minute
        _dueDate = State(initialValue: calendar.date(from: selected) ?? initialDate)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PetScreenBackground()

                ScrollView {
                    VStack(spacing: 20) {
                        VStack(spacing: 8) {
                            CareIcon(systemName: "plus", color: .pawPurple, size: 58)
                            Text(L10n.text(language.language, "A new care moment", "新しいケア"))
                                .font(.title2.bold())
                                .foregroundStyle(Color.pawInk)
                            Text(language.language == .japanese
                                ? "\(store.household?.petName ?? "ペット")に必要なことを追加しましょう。"
                                : "Add one clear task so everyone knows what \(store.household?.petName ?? "your pet") needs.")
                                .font(.subheadline)
                                .foregroundStyle(Color.pawMuted)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, 10)

                        HStack(spacing: 12) {
                            CareIcon(systemName: "calendar", color: .pawPurple, size: 46)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(L10n.text(language.language, "Scheduled for", "予定日"))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.pawMuted)
                                Text(scheduledDateText)
                                    .font(.headline)
                                    .foregroundStyle(Color.pawInk)
                            }
                            Spacer()
                        }
                        .petCard(padding: 14)

                        VStack(alignment: .leading, spacing: 12) {
                            fieldLabel(L10n.text(language.language, "Frequency", "頻度"), icon: "arrow.triangle.2.circlepath")
                            HStack(spacing: 10) {
                                typeButton(
                                    .oneOff,
                                    title: L10n.text(language.language, "One-time", "一回のみ"),
                                    detail: L10n.text(language.language, "A dated need", "指定日のケア"),
                                    icon: "calendar.badge.plus"
                                )
                                typeButton(
                                    .routine,
                                    title: L10n.text(language.language, "Routine", "繰り返し"),
                                    detail: L10n.text(language.language, "Choose days", "曜日を指定"),
                                    icon: "arrow.triangle.2.circlepath"
                                )
                            }
                            Text(kind == .routine
                                ? L10n.text(language.language, "Choose the days and time this repeats.", "繰り返す曜日と時間を選びます。")
                                : L10n.text(language.language, "This will appear only on the date you choose.", "選んだ日に一度だけ表示されます。"))
                                .font(.caption)
                                .foregroundStyle(Color.pawMuted)

                            if kind == .routine {
                                Text(L10n.text(language.language, "Repeats on", "繰り返す曜日"))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.pawPurpleDark)
                                HStack(spacing: 7) {
                                    ForEach(weekdayOptions, id: \.value) { day in
                                        Button(day.label) {
                                            if weekdays.contains(day.value), weekdays.count > 1 {
                                                weekdays.removeAll { $0 == day.value }
                                            } else {
                                                weekdays.append(day.value)
                                            }
                                        }
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(weekdays.contains(day.value) ? .white : Color.pawPurple)
                                        .frame(width: 34, height: 34)
                                        .background(
                                            weekdays.contains(day.value) ? Color.pawPurple : Color.pawLavender,
                                            in: Circle()
                                        )
                                    }
                                }
                            }
                        }
                        .petCard()

                        VStack(alignment: .leading, spacing: 13) {
                            fieldLabel(L10n.text(language.language, "Care category", "カテゴリー"), icon: "square.grid.2x2.fill")
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                                ForEach(CareCategory.allCases) { item in
                                    Button {
                                        category = item
                                    } label: {
                                        VStack(spacing: 7) {
                                            CareIcon(
                                                systemName: item.systemImage,
                                                color: item.accentColor,
                                                size: 42
                                            )
                                            Text(item.localizedTitle(for: language.language))
                                                .font(.caption2.weight(.semibold))
                                                .foregroundStyle(Color.pawInk)
                                                .lineLimit(1)
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(
                                            category == item
                                                ? item.accentColor.opacity(0.13)
                                                : Color.pawCream,
                                            in: RoundedRectangle(cornerRadius: 17)
                                        )
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 17)
                                                .stroke(
                                                    category == item ? item.accentColor : .clear,
                                                    lineWidth: 1.5
                                                )
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(item.localizedTitle(for: language.language))
                                    .accessibilityAddTraits(category == item ? .isSelected : [])
                                }
                            }
                        }
                        .petCard()

                        VStack(alignment: .leading, spacing: 9) {
                            fieldLabel(L10n.text(language.language, "What needs to be done?", "具体的な名前"), icon: "checklist")
                            TextField(L10n.text(language.language, "For example: Morning meal", "例：朝ごはん"), text: $title)
                                .petField()
                        }
                        .petCard()

                        VStack(alignment: .leading, spacing: 12) {
                            fieldLabel(
                                kind == .routine
                                    ? L10n.text(language.language, "Start date and time", "開始日と時間")
                                    : L10n.text(language.language, "Date and time", "日時"),
                                icon: "clock.fill"
                            )
                            DatePicker(
                                kind == .routine
                                    ? L10n.text(language.language, "Starts", "開始")
                                    : L10n.text(language.language, "Date", "日付"),
                                selection: $dueDate,
                                displayedComponents: .date
                            )
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.pawInk)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 52)
                            .background(Color.pawLavender.opacity(0.52), in: RoundedRectangle(cornerRadius: 15))

                            DatePicker(
                                L10n.text(language.language, "Time", "時間"),
                                selection: $dueDate,
                                displayedComponents: .hourAndMinute
                            )
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.pawInk)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 52)
                            .background(Color.pawLavender.opacity(0.52), in: RoundedRectangle(cornerRadius: 15))
                        }
                        .petCard()

                        HStack(spacing: 13) {
                            CareIcon(systemName: "exclamationmark.circle.fill", color: .pawRose, size: 48)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(L10n.text(language.language, "Urgent care", "緊急ケア"))
                                    .font(.headline)
                                    .foregroundStyle(Color.pawInk)
                                Text(L10n.text(language.language, "Make this stand out for both caregivers.", "家族全員に目立つようにします。"))
                                    .font(.caption)
                                    .foregroundStyle(Color.pawMuted)
                            }
                            Spacer()
                            Toggle(L10n.text(language.language, "Urgent", "緊急"), isOn: Binding(
                                get: { priority == .urgent },
                                set: { priority = $0 ? .urgent : .normal }
                            ))
                            .labelsHidden()
                            .tint(Color.pawRose)
                        }
                        .petCard(padding: 15)
                    }
                    .padding(20)
                    .padding(.bottom, 14)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(L10n.text(language.language, "Add Task", "ケアを追加"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.text(language.language, "Cancel", "キャンセル")) { dismiss() }
                        .accessibilityIdentifier("addTask.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            let saved = await store.addTask(
                                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                                category: category,
                                kind: kind,
                                priority: priority,
                                date: dueDate,
                                frequency: routineFrequency,
                                weekdays: weekdays
                            )
                            if saved {
                                dismiss()
                            }
                        }
                    } label: {
                        if store.isSavingTask {
                            ProgressView()
                        } else {
                            Text(L10n.text(language.language, "Save", "保存")).fontWeight(.bold)
                        }
                    }
                    .disabled(
                        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || store.isSavingTask
                    )
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("addTask.save")
                    .accessibilityLabel(L10n.text(language.language, "Save", "保存"))
                }
            }
        }
        .environment(\.timeZone, TimeZone(identifier: timeZoneIdentifier) ?? .current)
    }

    private func fieldLabel(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.pawPurpleDark)
    }

    private var weekdayOptions: [(value: Int, label: String)] {
        language.language == .japanese
            ? [(1, "日"), (2, "月"), (3, "火"), (4, "水"), (5, "木"), (6, "金"), (7, "土")]
            : [(1, "S"), (2, "M"), (3, "T"), (4, "W"), (5, "T"), (6, "F"), (7, "S")]
    }

    private var routineFrequency: CareRoutineFrequency {
        kind == .routine && weekdays.count < 7 ? .selectedDays : .daily
    }

    private var scheduledDateText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language.language.rawValue)
        formatter.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        formatter.dateFormat = language.language == .japanese ? "M月d日 (E)" : "EEEE, MMM d"
        return formatter.string(from: dueDate)
    }

    private func typeButton(
        _ item: CareTaskKind,
        title: String,
        detail: String,
        icon: String
    ) -> some View {
        Button {
            kind = item
        } label: {
            VStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                Text(title)
                    .font(.subheadline.bold())
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(kind == item ? Color.pawPurpleDark : Color.pawMuted)
            }
            .foregroundStyle(kind == item ? Color.pawPurple : Color.pawInk)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 92)
            .background(
                kind == item ? Color.pawLavender : Color.pawCream,
                in: RoundedRectangle(cornerRadius: 17)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 17)
                    .stroke(kind == item ? Color.pawPurple : .clear, lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(kind == item ? .isSelected : [])
    }
}
