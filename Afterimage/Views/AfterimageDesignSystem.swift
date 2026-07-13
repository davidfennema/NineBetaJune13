import SwiftUI

enum AfterimageLayout {
    static let margin: CGFloat = 24
    static let horizontalScreenMargin = margin
    static let primaryButtonHeight: CGFloat = 46
    static let primaryButtonCornerRadius: CGFloat = 8
    static let cardDialogCornerRadius: CGFloat = 8
    static let dialogHorizontalPadding = AfterimageSpacing.large
    static let dialogVerticalPadding: CGFloat = 26
    static let dialogMaxWidth: CGFloat = 340
    static let notificationHorizontalPadding: CGFloat = 18
    static let notificationVerticalPadding: CGFloat = 12
    static let notificationMaxWidth: CGFloat = 250
    static let contactSheetGridSpacing: CGFloat = 4
    static let rowSpacing = AfterimageSpacing.large
    static let headerTopSpacing: CGFloat = 32
    static let imageStageTopOffset: CGFloat = 112
    static let imageStageHeightRatio: CGFloat = 0.54
    static let imageStageControlOffset: CGFloat = 24
    static let imageStageSwipeOffset: CGFloat = 72
    static let shutterBottomOffset: CGFloat = 38
    static let decisionGroupOpticalOffset: CGFloat = 4
    static let contactSheetOpticalOffset: CGFloat = -4
    static let backControlSize: CGFloat = 34
    static let backIconSize: CGFloat = 14
    static let actionHeight = primaryButtonHeight
    static let controlCornerRadius = primaryButtonCornerRadius
    static let counterLockupSpacing: CGFloat = 12

    static var listRowInsets: EdgeInsets {
        EdgeInsets(top: 0, leading: margin, bottom: 0, trailing: margin)
    }

    static func listRowInsets(top: CGFloat, bottom: CGFloat) -> EdgeInsets {
        EdgeInsets(top: top, leading: margin, bottom: bottom, trailing: margin)
    }

    static func imageStage(in geometry: GeometryProxy) -> AfterimageImageStage {
        let side = min(
            geometry.size.width - (horizontalScreenMargin * 2),
            geometry.size.height * imageStageHeightRatio
        )
        let top = geometry.safeAreaInsets.top + imageStageTopOffset
        return AfterimageImageStage(
            side: side,
            top: top,
            centerX: geometry.size.width / 2
        )
    }

    static func closeControlY(in geometry: GeometryProxy) -> CGFloat {
        max(22, geometry.safeAreaInsets.top * 0.45)
    }
}

enum AfterimageSpacing {
    static let extraSmall: CGFloat = 4
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 24
    static let extraLarge: CGFloat = 32
}

enum AfterimageOpacity {
    static let dimmed: Double = 0.55
    static let disabled: Double = 0.38
    static let floatingOverlayBackground: Double = 0.9
    static let dialogScrim: Double = 0.62
    static let dialogBackground: Double = 0.72
    static let dialogStroke: Double = 0.1
    static let secondaryButtonBackground: Double = 0.06
    static let secondaryButtonStroke: Double = 0.11
    static let notificationBackground: Double = 0.58
    static let notificationStroke: Double = 0.12
    static let notificationText: Double = 0.78
}

enum AfterimageSurface {
    static let floatingOverlayMaterial: Material = .ultraThinMaterial
}

struct AfterimageImageStage {
    let side: CGFloat
    let top: CGFloat
    let centerX: CGFloat

    var centerY: CGFloat {
        top + side / 2
    }

    var bottom: CGFloat {
        top + side
    }
}

enum AfterimageType {
    static func system(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    static func mono(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    static let screenTitle = system(size: 28, weight: .semibold)
    static let rollTitle = system(size: 18, weight: .semibold)
    static let archiveTitle = system(size: 15, weight: .semibold)
    static let rollListStatus = system(size: 12, weight: .regular)
    static let rollListStyle = system(size: 10, weight: .medium)
    static let primaryAction = system(size: 15, weight: .semibold)
    static let metadata = system(size: 11, weight: .medium)
    static let body = system(size: 13, weight: .regular)
    static let caption = system(size: 11, weight: .medium)
    static let instrumentCaption = mono(size: 10, weight: .medium)
}

enum AfterimageMotion {
    static let transientDuration: Double = 0.24

    static let quick = Animation.easeInOut(duration: 0.15)
    static let standard = Animation.easeInOut(duration: transientDuration)
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

struct AfterimageCloseButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(AfterimagePressButtonStyle())
        .accessibilityLabel("Close")
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
                .frame(maxWidth: .infinity, minHeight: AfterimageLayout.primaryButtonHeight)
                .background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: AfterimageLayout.primaryButtonCornerRadius, style: .continuous))
        }
        .buttonStyle(AfterimagePressButtonStyle())
        .disabled(isDisabled)
    }
}

struct AfterimageSecondaryButton: View {
    let title: String
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(AfterimageType.primaryAction)
                .tracking(0.35)
                .foregroundStyle(.white.opacity(isDisabled ? AfterimageOpacity.disabled : 0.78))
                .frame(maxWidth: .infinity, minHeight: AfterimageLayout.primaryButtonHeight)
                .background(
                    .white.opacity(AfterimageOpacity.secondaryButtonBackground),
                    in: RoundedRectangle(cornerRadius: AfterimageLayout.primaryButtonCornerRadius, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: AfterimageLayout.primaryButtonCornerRadius, style: .continuous)
                        .stroke(.white.opacity(AfterimageOpacity.secondaryButtonStroke), lineWidth: 1)
                }
        }
        .buttonStyle(AfterimagePressButtonStyle())
        .disabled(isDisabled)
    }
}

struct AfterimageDialogSurface<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(.horizontal, AfterimageLayout.dialogHorizontalPadding)
            .padding(.vertical, AfterimageLayout.dialogVerticalPadding)
            .frame(maxWidth: AfterimageLayout.dialogMaxWidth)
            .background(AfterimageSurface.floatingOverlayMaterial, in: RoundedRectangle(cornerRadius: AfterimageLayout.cardDialogCornerRadius, style: .continuous))
            .background(.black.opacity(AfterimageOpacity.dialogBackground), in: RoundedRectangle(cornerRadius: AfterimageLayout.cardDialogCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: AfterimageLayout.cardDialogCornerRadius, style: .continuous)
                    .stroke(.white.opacity(AfterimageOpacity.dialogStroke), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.32), radius: 22, y: 12)
    }
}

struct AfterimageFloatingNotification: View {
    let text: String

    var body: some View {
        Text(text)
            .font(AfterimageType.caption)
            .tracking(0.55)
            .multilineTextAlignment(.center)
            .foregroundStyle(.white.opacity(AfterimageOpacity.notificationText))
            .lineLimit(5)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, AfterimageLayout.notificationHorizontalPadding)
            .padding(.vertical, AfterimageLayout.notificationVerticalPadding)
            .frame(maxWidth: AfterimageLayout.notificationMaxWidth)
            .background(
                AfterimageSurface.floatingOverlayMaterial,
                in: RoundedRectangle(cornerRadius: AfterimageLayout.cardDialogCornerRadius, style: .continuous)
            )
            .background(
                .black.opacity(AfterimageOpacity.notificationBackground),
                in: RoundedRectangle(cornerRadius: AfterimageLayout.cardDialogCornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AfterimageLayout.cardDialogCornerRadius, style: .continuous)
                    .stroke(.white.opacity(AfterimageOpacity.notificationStroke), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.24), radius: 12, y: 6)
    }
}

private struct AfterimageCardSurfaceModifier: ViewModifier {
    var fillOpacity = AfterimageOpacity.secondaryButtonBackground
    var strokeOpacity = AfterimageOpacity.dialogStroke

    func body(content: Content) -> some View {
        content
            .background(
                .white.opacity(fillOpacity),
                in: RoundedRectangle(cornerRadius: AfterimageLayout.cardDialogCornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AfterimageLayout.cardDialogCornerRadius, style: .continuous)
                    .stroke(.white.opacity(strokeOpacity), lineWidth: 1)
            }
    }
}

extension View {
    func afterimageCardSurface(
        fillOpacity: Double = AfterimageOpacity.secondaryButtonBackground,
        strokeOpacity: Double = AfterimageOpacity.dialogStroke
    ) -> some View {
        modifier(AfterimageCardSurfaceModifier(fillOpacity: fillOpacity, strokeOpacity: strokeOpacity))
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

struct NineInfoNoteView: View {
    let text: String

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            AfterimageDialogSurface {
                Text(text)
                    .font(.system(size: 19, weight: .regular))
                    .lineSpacing(3)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.76))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, AfterimageLayout.horizontalScreenMargin)
        }
    }
}
