import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: CareStore
    @EnvironmentObject private var language: AppLanguageStore

    var body: some View {
        ZStack {
            PetScreenBackground()

            Group {
                if store.isRestoringSession {
                    VStack(spacing: 16) {
                        Image(systemName: "pawprint.fill")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(Color.pawPurple)
                            .frame(width: 68, height: 68)
                            .background(.white, in: RoundedRectangle(cornerRadius: 22))
                            .shadow(color: Color.pawPurple.opacity(0.15), radius: 16, y: 8)
                        ProgressView("Loading your household…")
                            .foregroundStyle(Color.pawMuted)
                    }
                } else if store.household == nil {
                    CreateJoinView()
                } else {
                    TabView {
                        NavigationStack {
                            TodayView()
                        }
                        .tabItem {
                            Label(L10n.text(language.language, "Today", "今日"), systemImage: "checklist")
                        }

                        NavigationStack {
                            ScheduleView()
                        }
                        .tabItem {
                            Label(L10n.text(language.language, "Calendar", "カレンダー"), systemImage: "calendar")
                        }

                        NavigationStack {
                            ActivityView()
                        }
                        .tabItem {
                            Label(L10n.text(language.language, "Activity", "アクティビティ"), systemImage: "clock.arrow.circlepath")
                        }

                        NavigationStack {
                            PremiumView()
                        }
                        .tabItem {
                            Label("copaw Pro", systemImage: "crown.fill")
                        }
                    }
                    .tint(Color.pawPurple)
                    .toolbarBackground(.white, for: .tabBar)
                    .toolbarBackground(.visible, for: .tabBar)
                }
            }
        }
        .alert(L10n.text(language.language, "Something went wrong", "エラーが発生しました"), isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? L10n.text(language.language, "Please try again.", "もう一度お試しください。"))
        }
    }
}
