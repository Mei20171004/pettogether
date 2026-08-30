import SwiftUI

struct TaskCardView: View {
    @EnvironmentObject private var store: CareStore
    @EnvironmentObject private var language: AppLanguageStore
    let task: CareTask
    var showsDate = false
    @State private var showingCaregiverPicker = false

    private var isMutating: Bool {
        store.mutatingTaskIDs.contains(task.id)
    }

    private var isAssignedToCurrentCaregiver: Bool {
        task.assigneeID == store.currentCaregiver?.id
    }

    private var requestIsForCurrentCaregiver: Bool {
        task.assignmentRequest?.requestedToID == store.currentCaregiver?.id
    }

    private var requestWasSentByCurrentCaregiver: Bool {
        task.assignmentRequest?.requestedByID == store.currentCaregiver?.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .top, spacing: 12) {
                CareIcon(
                    systemName: task.category.systemImage,
                    color: task.category.accentColor,
                    size: 48
                )

                VStack(alignment: .leading, spacing: 7) {
                    Text(task.title)
                        .font(.headline)
                        .foregroundStyle(Color.pawInk)

                    Label(dateText, systemImage: "clock.fill")
                        .font(.caption)
                        .foregroundStyle(Color.pawMuted)

                    HStack(spacing: 7) {
                        PetTag(
                            title: task.kind == .routine
                                ? L10n.text(language.language, "Routine", "繰り返し")
                                : L10n.text(language.language, "One-time", "一回のみ"),
                            systemImage: task.kind == .routine
                                ? "arrow.triangle.2.circlepath"
                                : "calendar.badge.plus",
                            color: task.kind == .routine ? .pawPurple : .pawBlue
                        )

                        if task.priority == .urgent {
                            PetTag(
                                title: L10n.text(language.language, "Urgent", "緊急"),
                                systemImage: "exclamationmark.circle.fill",
                                color: .pawRose
                            )
                        }
                    }
                }

                Spacer(minLength: 4)

                Image(systemName: stateIcon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(stateColor)
                    .accessibilityHidden(true)
            }

            Divider().overlay(Color.pawPurple.opacity(0.08))

            HStack(spacing: 8) {
                Image(systemName: stateIcon)
                    .foregroundStyle(stateColor)
                Text(stateMessage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.pawInk)
            }

            actionButtons
        }
        .padding(15)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24)
                .stroke(stateColor.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: Color.pawPurpleDark.opacity(0.08), radius: 15, y: 8)
        .overlay(alignment: .topTrailing) {
            if isMutating {
                ProgressView()
                    .tint(stateColor)
                    .padding(14)
            }
        }
        .disabled(isMutating)
        .accessibilityElement(children: .contain)
        .confirmationDialog(
            L10n.text(language.language, "Choose who should take this", "担当者を選択"),
            isPresented: $showingCaregiverPicker,
            titleVisibility: .visible
        ) {
            ForEach(otherCaregivers) { caregiver in
                Button(caregiver.displayName) {
                    Task { await store.request(task, from: caregiver) }
                }
            }
            Button(L10n.text(language.language, "Cancel", "キャンセル"), role: .cancel) {}
        } message: {
            Text(L10n.text(
                language.language,
                "Only this caregiver will be asked, and they can accept or decline.",
                "この人だけに依頼します。引き受けるか断るかを選べます。"
            ))
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        switch task.status {
        case .unclaimed:
            if requestIsForCurrentCaregiver {
                HStack(spacing: 10) {
                    Button(L10n.text(language.language, "Decline", "断る")) {
                        Task { await store.declineRequest(for: task) }
                    }
                    .buttonStyle(PawCompactButtonStyle(color: .pawMuted))

                    Button(L10n.text(language.language, "Accept", "引き受ける")) {
                        Task { await store.acceptRequest(for: task) }
                    }
                    .buttonStyle(PawCompactButtonStyle(color: .pawPurple, filled: true))
                }
            } else if requestWasSentByCurrentCaregiver {
                HStack(spacing: 10) {
                    Button(L10n.text(language.language, "Cancel request", "依頼を取り消す")) {
                        Task { await store.cancelRequest(for: task) }
                    }
                    .buttonStyle(PawCompactButtonStyle(color: .pawMuted))

                    Button(L10n.text(language.language, "I’ll do it", "私がやる")) {
                        Task { await store.claim(task) }
                    }
                    .buttonStyle(PawCompactButtonStyle(color: .pawPurple, filled: true))
                }
            } else {
                VStack(spacing: 10) {
                    Button(L10n.text(language.language, "I’ll do it", "私がやる")) {
                        Task { await store.claim(task) }
                    }
                    .buttonStyle(PawCompactButtonStyle(color: .pawPurple, filled: true))

                    Button(L10n.text(language.language, "Let anyone take it", "誰でも引き受ける")) {
                        Task { await store.requestAnyone(for: task) }
                    }
                    .buttonStyle(PawCompactButtonStyle(color: .pawBlue))

                    Button(L10n.text(language.language, "Choose a person", "担当者を指定")) {
                        showingCaregiverPicker = true
                    }
                    .buttonStyle(PawCompactButtonStyle(color: .pawBlue))
                    .disabled(otherCaregivers.isEmpty)
                }
            }

        case .claimed:
            if isAssignedToCurrentCaregiver {
                Button(L10n.text(language.language, "Mark done", "完了にする")) {
                    Task { await store.complete(task) }
                }
                .buttonStyle(PawCompactButtonStyle(color: .pawGreen, filled: true))
            }

        case .completed:
            EmptyView()
        }
    }

    private var dateText: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: language.language.rawValue)
        formatter.timeZone = householdTimeZone
        formatter.dateStyle = showsDate ? .medium : .none
        formatter.timeStyle = .short
        return formatter.string(from: task.dueTime)
    }

    private var stateMessage: String {
        switch task.status {
        case .unclaimed:
            if let request = task.assignmentRequest {
                if requestIsForCurrentCaregiver {
                    return language.language == .japanese
                        ? "\(request.requestedByNameSnapshot)さんからの依頼"
                        : "\(request.requestedByNameSnapshot) asked you to take this"
                }
                if request.mode == .open {
                    return L10n.text(language.language, "Open to anyone in the household", "家族の誰でも引き受けられます")
                }
                return language.language == .japanese
                    ? "\(request.requestedToNameSnapshot ?? "担当者")さんの返事待ち"
                    : "Waiting for \(request.requestedToNameSnapshot ?? "a caregiver")"
            }
            return L10n.text(language.language, "Nobody has claimed this yet", "まだ担当者がいません")
        case .claimed:
            if isAssignedToCurrentCaregiver {
                return L10n.text(language.language, "You’re on it", "あなたが担当中")
            }
            return language.language == .japanese
                ? "\(task.assigneeNameSnapshot ?? "担当者")さんが担当中"
                : "\(task.assigneeNameSnapshot ?? "A caregiver") is on it"
        case .completed:
            let name = task.completedBy ?? "A caregiver"
            if let completedAt = task.completedAt {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: language.language.rawValue)
                formatter.timeZone = householdTimeZone
                formatter.dateStyle = .none
                formatter.timeStyle = .short
                return language.language == .japanese
                    ? "\(name)さんが完了 · \(formatter.string(from: completedAt))"
                    : "Done by \(name) · \(formatter.string(from: completedAt))"
            }
            return language.language == .japanese ? "\(name)さんが完了" : "Done by \(name)"
        }
    }

    private var householdTimeZone: TimeZone {
        TimeZone(identifier: store.household?.timeZoneIdentifier ?? "") ?? .current
    }

    private var otherCaregivers: [Caregiver] {
        store.caregivers.filter { $0.id != store.currentCaregiver?.id }
    }

    private var stateIcon: String {
        switch task.status {
        case .unclaimed:
            task.assignmentRequest == nil ? "person.crop.circle.badge.questionmark" : "paperplane.fill"
        case .claimed:
            "person.crop.circle.fill.badge.checkmark"
        case .completed:
            "checkmark.seal.fill"
        }
    }

    private var stateColor: Color {
        switch task.status {
        case .unclaimed: .pawRose
        case .claimed: .pawPurple
        case .completed: .pawGreen
        }
    }

    private var cardBackground: Color {
        switch task.status {
        case .unclaimed: .white.opacity(0.97)
        case .claimed: .pawLavender.opacity(0.92)
        case .completed: .pawGreen.opacity(0.10)
        }
    }
}
