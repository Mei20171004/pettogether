import SwiftUI

struct CreateJoinView: View {
    @EnvironmentObject private var store: CareStore
    @EnvironmentObject private var language: AppLanguageStore
    @State private var mode = Mode.create
    @State private var caregiverName = ""
    @State private var householdName = "Mochi Family"
    @State private var petName = "Mochi"
    @State private var inviteCode = ""

    private enum Mode: String, CaseIterable, Identifiable {
        case create = "Create"
        case join = "Join"

        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                PetScreenBackground()

                ScrollView {
                    VStack(spacing: 22) {
                        VStack(spacing: 0) {
                            PetArtwork(height: 230)

                            VStack(spacing: 9) {
                                HStack(spacing: 9) {
                                    Image(systemName: "pawprint.fill")
                                        .font(.headline)
                                        .foregroundStyle(Color.pawPurple)
                                        .frame(width: 36, height: 36)
                                        .background(Color.pawLavender, in: RoundedRectangle(cornerRadius: 12))
                                    Text("copaw")
                                        .font(.largeTitle.bold())
                                        .foregroundStyle(Color.pawInk)
                                }
                                Text(L10n.text(language.language, "Shared care, without the guesswork.", "迷わない、みんなのケア。"))
                                    .font(.subheadline)
                                    .foregroundStyle(Color.pawMuted)
                                Label(L10n.text(language.language, "A happier routine for every pet parent", "すべての飼い主に、もっと楽しい毎日を"), systemImage: "sparkles")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.pawPurple)
                            }
                            .padding(.top, 16)
                            .padding(.bottom, 20)
                        }
                        .background(.white.opacity(0.96), in: RoundedRectangle(cornerRadius: 28))
                        .clipShape(RoundedRectangle(cornerRadius: 28))
                        .shadow(color: Color.pawPurpleDark.opacity(0.12), radius: 24, y: 12)

                        VStack(spacing: 18) {
                            Picker(L10n.text(language.language, "Setup mode", "設定モード"), selection: $mode) {
                                ForEach(Mode.allCases) { mode in
                                    Text(mode == .create
                                        ? L10n.text(language.language, "Create a home", "家を作る")
                                        : L10n.text(language.language, "Join a home", "家に参加"))
                                        .tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)

                            VStack(alignment: .leading, spacing: 8) {
                                fieldLabel(L10n.text(language.language, "Your name", "あなたの名前"), icon: "person.fill")
                                TextField(L10n.text(language.language, "How should your family see you?", "家族に表示する名前"), text: $caregiverName)
                                    .textContentType(.name)
                                    .petField()
                            }

                            if mode == .create {
                                VStack(alignment: .leading, spacing: 8) {
                                    fieldLabel(L10n.text(language.language, "Household", "家の名前"), icon: "house.fill")
                                    TextField(L10n.text(language.language, "Household name", "家族の名前"), text: $householdName)
                                        .petField()
                                }
                                VStack(alignment: .leading, spacing: 8) {
                                    fieldLabel(L10n.text(language.language, "Your pet", "ペット"), icon: "pawprint.fill")
                                    TextField(L10n.text(language.language, "Pet name", "ペットの名前"), text: $petName)
                                        .petField()
                                }
                            } else {
                                VStack(alignment: .leading, spacing: 8) {
                                    fieldLabel(L10n.text(language.language, "Invite code", "招待コード"), icon: "person.2.fill")
                                    TextField(L10n.text(language.language, "Enter the six-character code", "6文字のコードを入力"), text: $inviteCode)
                                        .textInputAutocapitalization(.characters)
                                        .autocorrectionDisabled()
                                        .petField()
                                    Text(L10n.text(language.language, "Ask a caregiver in your household for their six-character code.", "家族から6文字の招待コードをもらってください。"))
                                        .font(.caption)
                                        .foregroundStyle(Color.pawMuted)
                                }
                            }
                        }
                        .petCard()

                        Button(action: submit) {
                            HStack(spacing: 9) {
                                if store.isLoading {
                                    ProgressView()
                                        .tint(.white)
                                }
                                Text(mode == .create
                                    ? L10n.text(language.language, "Create household", "家を作成")
                                    : L10n.text(language.language, "Join household", "家に参加"))
                                Image(systemName: "arrow.right")
                            }
                        }
                        .buttonStyle(PawPrimaryButtonStyle())
                        .disabled(!canSubmit || store.isLoading)

                        Text(L10n.text(language.language, "One shared place for meals, walks, medicine, and handoffs.", "食事、散歩、薬、引き継ぎをひとつに。"))
                            .font(.footnote)
                            .foregroundStyle(Color.pawMuted)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 22)
                    }
                    .padding(20)
                    .padding(.bottom, 20)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(AppLanguage.allCases) { item in
                            Button(item.label) { language.language = item }
                        }
                    } label: {
                        Image(systemName: "globe")
                            .foregroundStyle(Color.pawPurple)
                    }
                }
            }
        }
    }

    private func fieldLabel(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color.pawPurpleDark)
    }

    private var canSubmit: Bool {
        guard !caregiverName.trimmingCharacters(in: .whitespaces).isEmpty else {
            return false
        }
        if mode == .create {
            return !householdName.trimmingCharacters(in: .whitespaces).isEmpty
                && !petName.trimmingCharacters(in: .whitespaces).isEmpty
        }
        return !inviteCode.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func submit() {
        if mode == .create {
            store.createHousehold(
                name: householdName,
                petName: petName,
                caregiverName: caregiverName
            )
        } else {
            store.joinHousehold(inviteCode: inviteCode, caregiverName: caregiverName)
        }
    }
}
