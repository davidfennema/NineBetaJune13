import SwiftUI
import UIKit

struct IntroView: View {
    var buttonTitle = "Let's Go"
    let onBegin: () -> Void
    private let sampleImages = [
        "IntroHero",
        "IntroCarousel01",
        "IntroCarousel02",
        "IntroCarousel03"
    ]
    @State private var selectedSampleIndex = 0

    init(buttonTitle: String = "Let's Go", onBegin: @escaping () -> Void) {
        self.buttonTitle = buttonTitle
        self.onBegin = onBegin
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    IntroHeroCarousel(
                        imageNames: sampleImages,
                        selectedIndex: $selectedSampleIndex
                    )
                        .frame(height: geometry.size.height * 0.66)
                        .clipped()
                        .overlay(alignment: .bottom) {
                            ZStack(alignment: .bottom) {
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

                                if sampleImages.count > 1 {
                                    IntroPageControl(
                                        numberOfPages: sampleImages.count,
                                        currentPage: selectedSampleIndex
                                    )
                                    .frame(height: 18)
                                    .padding(.bottom, 34)
                                    .allowsHitTesting(false)
                                }
                            }
                        }

                    Spacer(minLength: 0)
                }
                .ignoresSafeArea(edges: .top)

                introPanel
                    .padding(.horizontal, NineLayout.horizontalScreenMargin)
                    .padding(.bottom, max(geometry.safeAreaInsets.bottom, 18))
            }
        }
    }

    private var introPanel: some View {
        VStack(spacing: NineSpacing.extraLarge) {
            VStack(spacing: NineSpacing.medium) {
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

            NinePrimaryButton(title: buttonTitle) {
                onBegin()
            }
        }
        .padding(.horizontal, NineSpacing.large + NineSpacing.small)
        .padding(.vertical, NineSpacing.extraLarge)
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

private struct IntroHeroCarousel: View {
    let imageNames: [String]
    @Binding var selectedIndex: Int

    var body: some View {
        TabView(selection: $selectedIndex) {
            ForEach(Array(imageNames.enumerated()), id: \.offset) { index, name in
                IntroHeroImage(name: name)
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }
}

private struct IntroPageControl: UIViewRepresentable {
    let numberOfPages: Int
    let currentPage: Int

    func makeUIView(context: Context) -> UIPageControl {
        let control = UIPageControl()
        control.isUserInteractionEnabled = false
        control.currentPageIndicatorTintColor = UIColor.white.withAlphaComponent(0.72)
        control.pageIndicatorTintColor = UIColor.white.withAlphaComponent(0.28)
        return control
    }

    func updateUIView(_ uiView: UIPageControl, context: Context) {
        uiView.numberOfPages = numberOfPages
        uiView.currentPage = currentPage
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
