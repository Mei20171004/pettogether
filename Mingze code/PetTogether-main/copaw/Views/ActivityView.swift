import SwiftUI

struct ActivityView: View {
    @EnvironmentObject private var store: CareStore
    @EnvironmentObject private var language: AppLanguageStore

    var body: some View {
        ZStack {
            PetScreenBackground()

            ScrollView {
                LazyVStack(spacing: 18) {
                    activitySummary

                    if completedTasks.isEmpty {
                        emptyState
                    } else {
                        PetSectionTitle(
                            title: "Care history",
                            detail: "\(completedTasks.count) COMPLETED"
                        )

                        ForEach(completedTasks) { task in
                            activityCard(task)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
        }
        .navigationTitle(L10n.text(language.language, "Activity", "アクティビティ"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var completedTasks: [CareTask] {
        store.tasks
            .filter { $0.status == .completed }
            .sorted { ($0.completedAt ?? $0.dueTime) > ($1.completedAt ?? $1.dueTime) }
    }

    private var activitySummary: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                Label("SHARED CARE", systemImage: "heart.fill")
                    .font(.caption2.bold())
                    .foregroundStyle(Color.pawPurple)
                Text("Every handoff,\nin one place.")
                    .font(.title2.bold())
                    .foregroundStyle(Color.pawInk)
                Text("See who cared for \(store.household?.petName ?? "your pet") and when.")
                    .font(.caption)
                    .foregroundStyle(Color.pawMuted)
            }
            Spacer()
            Image("CopawPets")
                .resizable()
                .scaledToFill()
                .frame(width: 124, height: 138)
                .clipShape(RoundedRectangle(cornerRadius: 20))
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [.pawPeach.opacity(0.8), .pawLavender],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 28)
        )
        .shadow(color: Color.pawPurpleDark.opacity(0.11), radius: 18, y: 9)
    }

    private func activityCard(_ task: CareTask) -> some View {
        HStack(alignment: .top, spacing: 13) {
            CareIcon(systemName: task.category.systemImage, color: task.category.accentColor, size: 50)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(task.title)
                        .font(.headline)
                        .foregroundStyle(Color.pawInk)
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.pawGreen)
                }
                Text(task.category.title.uppercased())
                    .font(.caption2.bold())
                    .foregroundStyle(task.category.accentColor)
                Label("Completed by \(task.completedBy ?? "A caregiver")", systemImage: "person.fill")
                    .font(.subheadline)
                    .foregroundStyle(Color.pawMuted)
                if let completedAt = task.completedAt {
                    Label(
                        completedAt.formatted(date: .abbreviated, time: .shortened),
                        systemImage: "clock.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(Color.pawMuted)
                }
            }
        }
        .petCard(padding: 15)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            CareIcon(systemName: "clock.arrow.circlepath", color: .pawPurple, size: 62)
            Text("No activity yet")
                .font(.title3.bold())
                .foregroundStyle(Color.pawInk)
            Text("Completed care tasks will appear here for the whole household.")
                .font(.subheadline)
                .foregroundStyle(Color.pawMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .petCard(padding: 28)
    }
}
