import SwiftUI
import UIKit

enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en"
    case japanese = "ja"

    var id: String { rawValue }
    var label: String { self == .english ? "English" : "日本語" }
}

@MainActor
final class AppLanguageStore: ObservableObject {
    @Published var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: "copaw.language")
        }
    }

    init() {
        language = AppLanguage(
            rawValue: UserDefaults.standard.string(forKey: "copaw.language") ?? "en"
        ) ?? .english
    }
}

enum L10n {
    static func text(_ language: AppLanguage, _ english: String, _ japanese: String) -> String {
        language == .japanese ? japanese : english
    }
}

extension Color {
    static let pawGreen = Color(red: 0.16, green: 0.55, blue: 0.39)
    static let pawCream = Color(red: 0.99, green: 0.98, blue: 0.96)
    static let pawBlue = Color(red: 0.35, green: 0.49, blue: 0.88)
    static let pawPurple = Color(red: 0.45, green: 0.39, blue: 0.91)
    static let pawPurpleDark = Color(red: 0.27, green: 0.23, blue: 0.55)
    static let pawLavender = Color(red: 0.93, green: 0.92, blue: 1.00)
    static let pawPeach = Color(red: 1.00, green: 0.86, blue: 0.79)
    static let pawRose = Color(red: 1.00, green: 0.63, blue: 0.62)
    static let pawYellow = Color(red: 1.00, green: 0.84, blue: 0.43)
    static let pawInk = Color(red: 0.15, green: 0.14, blue: 0.24)
    static let pawMuted = Color(red: 0.45, green: 0.44, blue: 0.56)
}

extension CareCategory {
    func localizedTitle(for language: AppLanguage) -> String {
        switch self {
        case .feeding: L10n.text(language, "Feeding", "食事")
        case .walking: L10n.text(language, "Walking", "散歩")
        case .medication: L10n.text(language, "Medication", "薬")
        case .grooming: L10n.text(language, "Grooming", "グルーミング")
        case .other: L10n.text(language, "Other", "その他")
        }
    }

    var accentColor: Color {
        switch self {
        case .feeding: .pawPurple
        case .walking: .pawBlue
        case .medication: .pawRose
        case .grooming: .pawYellow
        case .other: .pawGreen
        }
    }
}

struct PetScreenBackground: View {
    var body: some View {
        LinearGradient(
            colors: [.pawCream, .pawLavender.opacity(0.72)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

struct CareIcon: View {
    let systemName: String
    let color: Color
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.14), in: RoundedRectangle(cornerRadius: size * 0.32))
    }
}

struct PetArtwork: View {
    var height: CGFloat = 180

    var body: some View {
        Image("CopawPets")
            .resizable()
            .scaledToFill()
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .clipped()
    }
}

struct PetPhotoView: View {
    let data: Data?

    var body: some View {
        Group {
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image("DefaultPetPhoto")
                    .resizable()
                    .scaledToFill()
            }
        }
        .accessibilityHidden(true)
    }
}

enum PetPhotoError: LocalizedError {
    case unavailable
    case unsupported
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "The selected photo couldn't be loaded."
        case .unsupported:
            "That image format isn't supported."
        case .encodingFailed:
            "The selected photo couldn't be prepared."
        }
    }
}

func preparePetPhoto(_ sourceData: Data) throws -> Data {
    guard let sourceImage = UIImage(data: sourceData) else {
        throw PetPhotoError.unsupported
    }

    let maximumDimension: CGFloat = 1_600
    let longestSide = max(sourceImage.size.width, sourceImage.size.height)
    let scale = longestSide > maximumDimension ? maximumDimension / longestSide : 1
    let targetSize = CGSize(
        width: max(1, sourceImage.size.width * scale),
        height: max(1, sourceImage.size.height * scale)
    )
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    let image = UIGraphicsImageRenderer(size: targetSize, format: format).image { context in
        UIColor.white.setFill()
        context.fill(CGRect(origin: .zero, size: targetSize))
        sourceImage.draw(in: CGRect(origin: .zero, size: targetSize))
    }

    guard let data = image.jpegData(compressionQuality: 0.82) else {
        throw PetPhotoError.encodingFailed
    }
    return data
}

struct PetSectionTitle: View {
    let title: String
    var detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.bold())
                .foregroundStyle(Color.pawInk)
            Spacer()
            if let detail {
                Text(detail)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.pawPurple)
            }
        }
    }
}

struct PetTag: View {
    let title: String
    let systemImage: String
    let color: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption2.bold())
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(color.opacity(0.12), in: Capsule())
            .accessibilityElement(children: .combine)
    }
}

private struct PetCardModifier: ViewModifier {
    let padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(.white.opacity(0.96), in: RoundedRectangle(cornerRadius: 24))
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .stroke(.white.opacity(0.9), lineWidth: 1)
            }
            .shadow(color: Color.pawPurpleDark.opacity(0.09), radius: 18, y: 9)
    }
}

private struct PetFieldModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14)
            .frame(minHeight: 50)
            .background(Color.pawLavender.opacity(0.52), in: RoundedRectangle(cornerRadius: 15))
            .overlay {
                RoundedRectangle(cornerRadius: 15)
                    .stroke(Color.pawPurple.opacity(0.08), lineWidth: 1)
            }
    }
}

extension View {
    func petCard(padding: CGFloat = 18) -> some View {
        modifier(PetCardModifier(padding: padding))
    }

    func petField() -> some View {
        modifier(PetFieldModifier())
    }
}

struct PawPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 54)
            .background(
                LinearGradient(
                    colors: [.pawPurple, .pawBlue],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: RoundedRectangle(cornerRadius: 18)
            )
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .shadow(color: Color.pawPurple.opacity(0.22), radius: 12, y: 7)
    }
}

struct PawCompactButtonStyle: ButtonStyle {
    let color: Color
    var filled = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.bold))
            .foregroundStyle(filled ? .white : color)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .background(
                filled ? color : color.opacity(0.12),
                in: RoundedRectangle(cornerRadius: 14)
            )
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}
