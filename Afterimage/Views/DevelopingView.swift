import SwiftUI

struct DevelopingView: View {
    @State private var breath = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 26) {
                Circle()
                    .fill(.white.opacity(0.7))
                    .frame(width: 5, height: 5)
                    .scaleEffect(breath ? 1.7 : 0.8)
                    .opacity(breath ? 0.45 : 1)
                    .animation(AfterimageMotion.breath, value: breath)
                Text("Developing Roll...")
                    .font(AfterimageType.rollTitle)
                    .tracking(0.2)
                    .foregroundStyle(.white.opacity(0.86))
            }
        }
        .onAppear { breath = true }
    }
}
