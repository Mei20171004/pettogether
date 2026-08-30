import SwiftUI
import UIKit

struct ProfileEditView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: CareStore

    @State private var caregiverName = ""
    @State private var householdName = ""
    @State private var petName = ""
    @State private var copiedInvite = false
    @State private var isConfirmingLeave = false
    @State private var didLoadProfile = false
    @FocusState private var focusedField: Field?

    private enum Field {
        case caregiverName
        case householdName
        case petName
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PetScreenBackground()

                ScrollView {
                    VStack(spacing: 18) {
                        profileHeader
                        caregiverCard
                        householdCard
                        inviteCard

                        Button {
                            save()
                        } label: {
                            HStack(spacing: 9) {
                                if store.isSavingProfile {
                                    ProgressView()
                                        .tint(.white)
                                }
                                Text(store.isSavingProfile ? "Saving…" : "Save changes")
                                if !store.isSavingProfile {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        .buttonStyle(PawPrimaryButtonStyle())
                        .disabled(!canSave || store.isSavingProfile)

                        Text("Changes are shared with everyone in this household.")
                            .font(.caption)
                            .foregroundStyle(Color.pawMuted)
                            .multilineTextAlignment(.center)

                        leaveHouseholdCard
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                    .padding(.bottom, 28)
                }
            }
            .navigationTitle("Family profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .interactiveDismissDisabled(store.isSavingProfile)
        .onAppear(perform: loadProfileIfNeeded)
        .alert("Leave this household?", isPresented: $isConfirmingLeave) {
            Button("Cancel", role: .cancel) {}
            Button("Leave household", role: .destructive) {
                store.leaveHousehold()
                dismiss()
            }
        } message: {
            Text("This device will return to the welcome screen. The shared household stays available to other caregivers, and you can rejoin later with the invite code.")
        }
    }

    private var profileHeader: some View {
        VStack(spacing: 12) {
            Text(caregiverInitial)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(Color.pawPurple)
                .frame(width: 74, height: 74)
                .background(.white, in: RoundedRectangle(cornerRadius: 24))
                .shadow(color: Color.pawPurple.opacity(0.14), radius: 14, y: 7)

            VStack(spacing: 4) {
                Text("Keep your family details current")
                    .font(.title3.bold())
                    .foregroundStyle(Color.pawInk)
                Text("Your name and pet details update across devices.")
                    .font(.subheadline)
                    .foregroundStyle(Color.pawMuted)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var caregiverCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            PetSectionTitle(title: "About you", detail: "CAREGIVER")
            fieldLabel("Your name", icon: "person.fill")
            TextField("How should your family see you?", text: $caregiverName)
                .textContentType(.name)
                .textInputAutocapitalization(.words)
                .submitLabel(.next)
                .focused($focusedField, equals: .caregiverName)
                .onSubmit { focusedField = .householdName }
                .petField()
        }
        .petCard()
    }

    private var householdCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            PetSectionTitle(title: "Home & pet", detail: "SHARED")

            fieldLabel("Household name", icon: "house.fill")
            TextField("Household name", text: $householdName)
                .textInputAutocapitalization(.words)
                .submitLabel(.next)
                .focused($focusedField, equals: .householdName)
                .onSubmit { focusedField = .petName }
                .petField()

            fieldLabel("Pet name", icon: "pawprint.fill")
                .padding(.top, 4)
            TextField("Pet name", text: $petName)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .focused($focusedField, equals: .petName)
                .onSubmit { focusedField = nil }
                .petField()

        }
        .petCard()
    }

    @ViewBuilder
    private var inviteCard: some View {
        if let inviteCode = store.household?.inviteCode, !inviteCode.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                PetSectionTitle(title: "Invite a caregiver", detail: "SHARE ACCESS")

                HStack(spacing: 12) {
                    CareIcon(systemName: "person.2.fill", color: .pawBlue, size: 50)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Invite code")
                            .font(.caption)
                            .foregroundStyle(Color.pawMuted)
                        Text(inviteCode)
                            .font(.system(.title3, design: .monospaced, weight: .bold))
                            .foregroundStyle(Color.pawInk)
                            .tracking(1.2)
                    }

                    Spacer(minLength: 4)

                    Button {
                        copyInviteCode(inviteCode)
                    } label: {
                        Label(
                            copiedInvite ? "Copied" : "Copy",
                            systemImage: copiedInvite ? "checkmark" : "doc.on.doc"
                        )
                        .font(.caption.weight(.bold))
                        .frame(minWidth: 72)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                        .foregroundStyle(Color.pawPurple)
                        .background(Color.pawLavender, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Copies the household invite code")
                }

                Text("Share this code with someone you trust so they can join this household.")
                    .font(.caption)
                    .foregroundStyle(Color.pawMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .petCard()
        }
    }

    private var leaveHouseholdCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Household membership")
                .font(.headline)
                .foregroundStyle(Color.pawInk)
            Text("Return this device to the welcome screen without deleting shared household data.")
                .font(.subheadline)
                .foregroundStyle(Color.pawMuted)

            Button(role: .destructive) {
                isConfirmingLeave = true
            } label: {
                Label("Leave household", systemImage: "rectangle.portrait.and.arrow.right")
                    .font(.subheadline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 48)
                    .foregroundStyle(Color.red)
                    .background(Color.red.opacity(0.09), in: RoundedRectangle(cornerRadius: 15))
            }
            .buttonStyle(.plain)
            .disabled(store.isSavingProfile)
        }
        .petCard()
    }

    private func fieldLabel(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.pawPurpleDark)
    }

    private var caregiverInitial: String {
        caregiverName.trimmingCharacters(in: .whitespacesAndNewlines)
            .first
            .map { String($0).uppercased() } ?? "?"
    }

    private var canSave: Bool {
        let caregiverName = caregiverName.trimmingCharacters(in: .whitespacesAndNewlines)
        let householdName = householdName.trimmingCharacters(in: .whitespacesAndNewlines)
        let petName = petName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !caregiverName.isEmpty
            && caregiverName.count <= 50
            && !householdName.isEmpty
            && householdName.count <= 60
            && !petName.isEmpty
            && petName.count <= 60
    }

    private func loadProfileIfNeeded() {
        guard !didLoadProfile else { return }
        caregiverName = store.currentCaregiver?.displayName ?? ""
        householdName = store.household?.name ?? ""
        petName = store.household?.petName ?? ""
        didLoadProfile = true
    }

    private func save() {
        focusedField = nil
        Task {
            if await store.updateProfile(
                caregiverName: caregiverName,
                householdName: householdName,
                petName: petName
            ) {
                dismiss()
            }
        }
    }

    private func copyInviteCode(_ inviteCode: String) {
        UIPasteboard.general.string = inviteCode
        copiedInvite = true

        Task {
            try? await Task.sleep(for: .seconds(2))
            copiedInvite = false
        }
    }
}
