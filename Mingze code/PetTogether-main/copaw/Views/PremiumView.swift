import SwiftUI

struct PremiumView: View {
    @EnvironmentObject private var language: AppLanguageStore
    @State private var showPrototypeMessage = false

    var body: some View {
        ZStack {
            PetScreenBackground()

            ScrollView {
                VStack(spacing: 20) {
                    hero

                    VStack(alignment: .leading, spacing: 14) {
                        PetSectionTitle(title: "Made for the whole family", detail: "PRO")
                        feature("Unlimited pets and caregivers", icon: "person.3.fill", color: .pawPurple)
                        feature("Recurring medication routines", icon: "pills.fill", color: .pawRose)
                        feature("Complete care history", icon: "clock.arrow.circlepath", color: .pawBlue)
                        feature("Pet sitter handoff mode", icon: "hand.wave.fill", color: .pawYellow)
                        feature("Smart care reminders", icon: "sparkles", color: .pawGreen)
                    }
                    .petCard()

                    HStack(spacing: 12) {
                        priceCard(title: "Monthly", price: "¥300", detail: "per month")
                        priceCard(title: "Annual", price: "¥2,000", detail: "per year")
                    }

                    Button {
                        showPrototypeMessage = true
                    } label: {
                        HStack(spacing: 8) {
                            Text("Start Free Trial")
                            Image(systemName: "arrow.right")
                        }
                    }
                    .buttonStyle(PawPrimaryButtonStyle())

                    Text("Prototype pricing. Payment is not enabled in this build.")
                        .font(.caption)
                        .foregroundStyle(Color.pawMuted)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
        }
        .navigationTitle("copaw Pro")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Prototype package", isPresented: $showPrototypeMessage) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Payments are not enabled in this prototype.")
        }
    }

    private var hero: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                PetArtwork(height: 210)
                Label("FAMILY PRO", systemImage: "crown.fill")
                    .font(.caption2.bold())
                    .foregroundStyle(Color.pawPurpleDark)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(.white.opacity(0.88), in: Capsule())
                    .padding(14)
            }

            VStack(spacing: 8) {
                Text("More love. Less mental load.")
                    .font(.title2.bold())
                    .foregroundStyle(Color.pawInk)
                    .multilineTextAlignment(.center)
                Text("Build a calmer care routine for every pet and every caregiver.")
                    .font(.subheadline)
                    .foregroundStyle(Color.pawMuted)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 22)
            .padding(.top, 16)
            .padding(.bottom, 20)
        }
        .background(.white.opacity(0.96), in: RoundedRectangle(cornerRadius: 28))
        .clipShape(RoundedRectangle(cornerRadius: 28))
        .shadow(color: Color.pawPurpleDark.opacity(0.12), radius: 22, y: 11)
    }

    private func feature(_ text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 12) {
            CareIcon(systemName: icon, color: color, size: 42)
            Text(text)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.pawInk)
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.pawGreen)
        }
    }

    private func priceCard(title: String, price: String, detail: String) -> some View {
        VStack(spacing: 7) {
            if title == "Annual" {
                Text("BEST VALUE")
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.pawPurple, in: Capsule())
            } else {
                Text("FLEXIBLE")
                    .font(.caption2.bold())
                    .foregroundStyle(Color.pawMuted)
                    .padding(.vertical, 5)
            }
            Text(title)
                .font(.headline)
                .foregroundStyle(Color.pawInk)
            Text(price)
                .font(.title2.bold())
                .foregroundStyle(Color.pawPurpleDark)
            Text(detail)
                .font(.caption)
                .foregroundStyle(Color.pawMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(
            title == "Annual" ? Color.pawLavender : Color.white.opacity(0.94),
            in: RoundedRectangle(cornerRadius: 22)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .stroke(title == "Annual" ? Color.pawPurple : Color.white, lineWidth: 1.5)
        }
        .shadow(color: Color.pawPurpleDark.opacity(0.08), radius: 12, y: 6)
    }
}
