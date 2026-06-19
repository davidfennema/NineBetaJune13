import SwiftUI

struct IntroView: View {
    var buttonTitle = "Begin"
    let onBegin: () -> Void

    private static let heroImages = [
        "IntroHero01",
        "IntroHero02",
        "IntroHero03",
        "IntroHero04"
    ]
    @State private var selectedHeroImage: String

    init(buttonTitle: String = "Begin", onBegin: @escaping () -> Void) {
        self.buttonTitle = buttonTitle
        self.onBegin = onBegin
        _selectedHeroImage = State(initialValue: Self.heroImages.randomElement() ?? "IntroHero01")
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    IntroHeroImage(name: selectedHeroImage)
                        .frame(height: geometry.size.height * 0.66)
                        .clipped()
                        .overlay(alignment: .bottom) {
                            LinearGradient(
                                colors: [
                                    .black.opacity(0),
                                    .black.opacity(0.72),
                                    .black
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 180)
                            .allowsHitTesting(false)
                        }

                    Spacer(minLength: 0)
                }
                .ignoresSafeArea(edges: .top)

                introPanel
                    .padding(.horizontal, 24)
                    .padding(.bottom, max(geometry.safeAreaInsets.bottom, 18))
            }
        }
    }

    private var introPanel: some View {
        VStack(spacing: 24) {
            VStack(spacing: 14) {
                Text("Nine")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.94))

                Text("Shoot nine frames.\nReload the roll.\nShoot nine more.\nCreate something unexpected.")
                    .font(.system(size: 17, weight: .regular))
                    .lineSpacing(5)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: onBegin) {
                Text(buttonTitle)
                    .font(AfterimageType.primaryAction)
                    .foregroundStyle(.black.opacity(0.92))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(
                        .white.opacity(0.92),
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                    )
            }
            .buttonStyle(AfterimagePressButtonStyle())
        }
        .padding(.horizontal, 22)
        .padding(.top, 28)
        .padding(.bottom, 22)
        .background(
            LinearGradient(
                colors: [
                    .white.opacity(0.105),
                    .white.opacity(0.055)
                ],
                startPoint: .top,
                endPoint: .bottom
            ),
            in: UnevenRoundedRectangle(
                topLeadingRadius: 24,
                bottomLeadingRadius: 14,
                bottomTrailingRadius: 14,
                topTrailingRadius: 24,
                style: .continuous
            )
        )
        .overlay {
            UnevenRoundedRectangle(
                topLeadingRadius: 24,
                bottomLeadingRadius: 14,
                bottomTrailingRadius: 14,
                topTrailingRadius: 24,
                style: .continuous
            )
            .stroke(.white.opacity(0.09), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.32), radius: 22, y: 12)
    }
}

private struct IntroHeroImage: View {
    let name: String

    var body: some View {
        GeometryReader { geometry in
            Image(name)
                .resizable()
                .scaledToFill()
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
        }
    }
}
