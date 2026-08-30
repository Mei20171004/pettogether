import SwiftUI
import PhotosUI

struct TodayView: View {
    @EnvironmentObject private var store: CareStore
    @EnvironmentObject private var language: AppLanguageStore
    @State private var isAddingTask = false
    @State private var isEditingProfile = false
    @State private var selectedPetPhotoItem: PhotosPickerItem?
    @State private var isLoadingPetPhoto = false
    @State private var petPhotoErrorMessage: String?

    var body: some View {
        ZStack {
            PetScreenBackground()

            ScrollView {
                LazyVStack(spacing: 20) {
                    greetingHeader
                    petHeroCard
                    unclaimedSection
                    claimedSection
                    completedSection
                    careCategories
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
        }
        .navigationTitle(L10n.text(language.language, "Today", "今日"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    ForEach(AppLanguage.allCases) { item in
                        Button {
                            language.language = item
                        } label: {
                            Label(item.label, systemImage: language.language == item ? "checkmark" : "globe")
                        }
                    }
                } label: {
                    Image(systemName: "globe")
                        .foregroundStyle(Color.pawPurple)
                }
                .accessibilityLabel(L10n.text(language.language, "Language", "言語"))
            }
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
                .accessibilityLabel("Add task")
            }
        }
        .sheet(isPresented: $isAddingTask) {
            AddTaskView(
                timeZoneIdentifier: store.household?.timeZoneIdentifier ?? TimeZone.current.identifier
            )
        }
        .sheet(isPresented: $isEditingProfile) {
            ProfileEditView()
        }
        .onChange(of: selectedPetPhotoItem) { _, newItem in
            guard let newItem else { return }
            updatePetPhoto(from: newItem)
        }
        .alert("Couldn't use that photo", isPresented: Binding(
            get: { petPhotoErrorMessage != nil },
            set: { if !$0 { petPhotoErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(petPhotoErrorMessage ?? "Please choose another image.")
        }
    }

    private var greetingHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Hi, \(store.currentCaregiver?.displayName ?? "pet parent")")
                    .font(.title2.bold())
                    .foregroundStyle(Color.pawInk)
                Text("Let’s make today a happy one.")
                    .font(.subheadline)
                    .foregroundStyle(Color.pawMuted)
            }
            Spacer()
            Button {
                isEditingProfile = true
            } label: {
                Image(systemName: "person.fill")
                    .foregroundStyle(Color.pawPurple)
                    .frame(width: 44, height: 44)
                    .background(.white, in: RoundedRectangle(cornerRadius: 15))
                    .shadow(color: Color.pawPurple.opacity(0.12), radius: 10, y: 5)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit family profile")
        }
    }

    private var petHeroCard: some View {
        let petPhotoData = store.petPhotoData

        return HStack(spacing: 4) {
            VStack(alignment: .leading, spacing: 9) {
                Label("CARE PULSE", systemImage: "sparkles")
                    .font(.caption2.bold())
                    .foregroundStyle(Color.pawPurple)
                Text(store.household?.petName ?? "Your pet")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.pawInk)
                Text(careSummary)
                    .font(.subheadline)
                    .foregroundStyle(Color.pawMuted)
                    .fixedSize(horizontal: false, vertical: true)
                Label(store.household?.name ?? "Your household", systemImage: "house.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.pawPurpleDark)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            PhotosPicker(selection: $selectedPetPhotoItem, matching: .images) {
                ZStack(alignment: .bottomTrailing) {
                    PetPhotoView(data: petPhotoData)
                        .frame(width: 138, height: 156)
                        .clipShape(RoundedRectangle(cornerRadius: 21))

                    Group {
                        if isLoadingPetPhoto {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: 34, height: 34)
                    .background(Color.pawPurple, in: Circle())
                    .overlay {
                        Circle()
                            .stroke(.white, lineWidth: 3)
                    }
                    .offset(x: 5, y: 5)
                }
            }
            .buttonStyle(.plain)
            .disabled(isLoadingPetPhoto)
            .accessibilityLabel("Change pet photo")
            .accessibilityHint("Choose a photo from your library")
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [.pawLavender, .pawPeach.opacity(0.72)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 28)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 28)
                .stroke(.white.opacity(0.8), lineWidth: 1)
        }
        .shadow(color: Color.pawPurpleDark.opacity(0.12), radius: 20, y: 10)
    }

    private var careSummary: String {
        let count = store.unclaimedTasks.count + store.claimedTasks.count
        if count == 0 {
            return "Everything is handled. Time for cuddles."
        }
        return "\(count) care \(count == 1 ? "moment" : "moments") left for today."
    }

    private func updatePetPhoto(from item: PhotosPickerItem) {
        isLoadingPetPhoto = true
        petPhotoErrorMessage = nil

        Task {
            defer {
                isLoadingPetPhoto = false
                selectedPetPhotoItem = nil
            }
            do {
                guard let sourceData = try await item.loadTransferable(type: Data.self) else {
                    throw PetPhotoError.unavailable
                }
                let preparedData = try await Task.detached(priority: .userInitiated) {
                    try preparePetPhoto(sourceData)
                }.value
                try store.savePetPhoto(preparedData)
            } catch {
                petPhotoErrorMessage = (error as? LocalizedError)?.errorDescription
                    ?? "Please choose another image."
            }
        }
    }

    private var careCategories: some View {
        VStack(alignment: .leading, spacing: 12) {
            PetSectionTitle(title: "Daily care", detail: "AT A GLANCE")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                categoryTile(.feeding, shortTitle: "Meals")
                categoryTile(.walking, shortTitle: "Walks")
                categoryTile(.medication, shortTitle: "Meds")
                categoryTile(.grooming, shortTitle: "Groom")
            }
        }
    }

    private func categoryTile(_ category: CareCategory, shortTitle: String) -> some View {
        VStack(spacing: 8) {
            CareIcon(systemName: category.systemImage, color: category.accentColor, size: 42)
            Text(shortTitle)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Color.pawInk)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.white.opacity(0.94), in: RoundedRectangle(cornerRadius: 18))
        .shadow(color: Color.pawPurpleDark.opacity(0.07), radius: 10, y: 5)
    }

    private var unclaimedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            PetSectionTitle(
                title: "Needs a person",
                detail: store.unclaimedTasks.isEmpty ? "CLEAR" : "\(store.unclaimedTasks.count) UNCLAIMED"
            )

            if store.unclaimedTasks.isEmpty {
                emptyTasksState
            } else {
                ForEach(store.unclaimedTasks) { task in
                    TaskCardView(task: task)
                }
            }
        }
    }

    @ViewBuilder
    private var claimedSection: some View {
        if !store.claimedTasks.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                PetSectionTitle(title: "In progress", detail: "\(store.claimedTasks.count) CLAIMED")
                ForEach(store.claimedTasks) { task in
                    TaskCardView(task: task)
                }
            }
        }
    }

    @ViewBuilder
    private var completedSection: some View {
        if !store.completedTasks.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                PetSectionTitle(title: "Done today", detail: "SHARED CARE")
                ForEach(store.completedTasks.prefix(3)) { task in
                    TaskCardView(task: task)
                }
            }
        }
    }

    private var emptyTasksState: some View {
        VStack(spacing: 10) {
            CareIcon(systemName: "checkmark", color: .pawGreen, size: 56)
            Text("Everything is handled")
                .font(.headline)
                .foregroundStyle(Color.pawInk)
            Text("Add another task when your pet needs care.")
                .font(.subheadline)
                .foregroundStyle(Color.pawMuted)
                .multilineTextAlignment(.center)
            Button("Add a task") { isAddingTask = true }
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.pawPurple)
        }
        .frame(maxWidth: .infinity)
        .petCard()
    }

}
