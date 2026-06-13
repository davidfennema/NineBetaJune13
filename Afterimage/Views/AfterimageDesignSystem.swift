import SwiftUI

enum AfterimageLayout {
    static let margin: CGFloat = 24
    static let rowSpacing: CGFloat = 24
    static let headerTopSpacing: CGFloat = 32
    static let backControlSize: CGFloat = 34
    static let backIconSize: CGFloat = 14
    static let actionHeight: CGFloat = 46
    static let controlCornerRadius: CGFloat = 8
    static let counterLockupSpacing: CGFloat = 12

    static var listRowInsets: EdgeInsets {
        EdgeInsets(top: 0, leading: margin, bottom: 0, trailing: margin)
    }

    static func listRowInsets(top: CGFloat, bottom: CGFloat) -> EdgeInsets {
        EdgeInsets(top: top, leading: margin, bottom: bottom, trailing: margin)
    }
}

enum AfterimageType {
    static func mono(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static let screenTitle = mono(size: 28, weight: .medium)
    static let rollTitle = mono(size: 18, weight: .medium)
    static let archiveTitle = mono(size: 15, weight: .medium)
    static let primaryAction = mono(size: 15, weight: .semibold)
    static let metadata = mono(size: 11, weight: .medium)
    static let body = mono(size: 12, weight: .regular)
    static let caption = mono(size: 10, weight: .medium)
}

enum AfterimageMotion {
    static let quick = Animation.easeInOut(duration: 0.15)
    static let standard = Animation.easeInOut(duration: 0.24)
    static let reveal = Animation.easeInOut(duration: 0.32)
    static let longReveal = Animation.easeInOut(duration: 0.42)
    static let breath = Animation.easeInOut(duration: 1.4).repeatForever(autoreverses: true)

    static let screenTransition = AnyTransition.opacity
        .combined(with: .scale(scale: 0.985, anchor: .center))
        .combined(with: .offset(y: 6))

    static let cameraTransition = AnyTransition.opacity

    static let subtleTransition = AnyTransition.opacity
        .combined(with: .scale(scale: 0.985, anchor: .center))

    static let toastTransition = AnyTransition.opacity
        .combined(with: .offset(y: 10))
}

struct AfterimagePressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(AfterimageMotion.quick, value: configuration.isPressed)
    }
}

struct AfterimageBackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: AfterimageLayout.backIconSize, weight: .medium))
                .foregroundStyle(.white.opacity(0.54))
                .frame(
                    width: AfterimageLayout.backControlSize,
                    height: AfterimageLayout.backControlSize,
                    alignment: .leading
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(AfterimagePressButtonStyle())
        .accessibilityLabel("Back")
    }
}

struct AfterimagePrimaryButton: View {
    let title: String
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(AfterimageType.primaryAction)
                .tracking(0.35)
                .foregroundStyle(.black.opacity(isDisabled ? 0.45 : 0.92))
                .frame(maxWidth: .infinity, minHeight: AfterimageLayout.actionHeight)
                .background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: AfterimageLayout.controlCornerRadius, style: .continuous))
        }
        .buttonStyle(AfterimagePressButtonStyle())
        .disabled(isDisabled)
    }
}

struct AfterimageMetadataLabel: View {
    let text: String
    var opacity: Double = 0.42
    var tracking: CGFloat = 1.2

    var body: some View {
        Text(text)
            .font(AfterimageType.metadata)
            .tracking(tracking)
            .foregroundStyle(.white.opacity(opacity))
    }
}
