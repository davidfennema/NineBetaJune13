import SwiftUI

struct ViewfinderInfoOverlay: View {
    let zoomFactor: CGFloat
    let exposureBias: Float
    let isFocusLocked: Bool

    private let glowColor = Color(red: 1.0, green: 0.31, blue: 0.18)

    var body: some View {
        HStack(alignment: .center) {
            Text(zoomText)
                .font(displayFont(size: 16.25, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(glowColor.opacity(0.88))
                .contentTransition(.opacity)
                .animation(AfterimageMotion.quick, value: zoomText)
                .shadow(color: glowColor.opacity(0.26), radius: 4)

            Spacer(minLength: 18)

            Text("AF LOCK")
                .font(displayFont(size: 15, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(glowColor.opacity(0.86))
                .opacity(isFocusLocked ? 1 : 0)
                .animation(AfterimageMotion.quick, value: isFocusLocked)
                .shadow(color: glowColor.opacity(isFocusLocked ? 0.28 : 0), radius: 4)

            Spacer(minLength: 18)

            Text(exposureText)
                .font(displayFont(size: 16.25, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(glowColor.opacity(0.88))
                .contentTransition(.opacity)
                .animation(AfterimageMotion.quick, value: exposureText)
                .shadow(color: glowColor.opacity(0.26), radius: 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(
            LinearGradient(
                colors: [
                    .black.opacity(0),
                    .black.opacity(0.25)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .allowsHitTesting(false)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var zoomText: String {
        String(format: "%.1fx", zoomFactor)
    }

    private var exposureText: String {
        let rounded = (exposureBias * 10).rounded() / 10
        if rounded == 0 {
            return "0.0"
        }
        return String(format: "%+.1f", rounded)
    }

    private var accessibilityText: String {
        let focus = isFocusLocked ? ", autofocus locked" : ""
        return "Zoom \(zoomText), exposure compensation \(exposureText)\(focus)"
    }

    private func displayFont(size: CGFloat, weight: Font.Weight) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}
