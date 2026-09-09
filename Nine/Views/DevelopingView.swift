import SwiftUI

struct DevelopingView: View {
    @State private var breath = false
    @State private var showsMessage = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if showsMessage {
                VStack(spacing: 26) {
                    Circle()
                        .fill(.white.opacity(0.7))
                        .frame(width: 5, height: 5)
                        .scaleEffect(breath ? 1.7 : 0.8)
                        .opacity(breath ? 0.45 : 1)
                        .animation(NineMotion.breath, value: breath)
                    Text("Developing roll")
                        .font(NineType.rollTitle)
                        .tracking(0.2)
                        .foregroundStyle(.white.opacity(0.86))
                }
                .transition(NineMotion.subtleTransition)
            }
        }
        .task {
            try? await Task.sleep(for: .milliseconds(650))
            withAnimation(NineMotion.standard) {
                showsMessage = true
                breath = true
            }
        }
    }
}
