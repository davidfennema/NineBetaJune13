import SwiftUI

struct DevelopingView: View {
    @ObservedObject var viewModel: RollViewModel
    var onReturnHome: (() -> Void)?
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
        .overlay {
            if viewModel.persistenceError != nil || viewModel.developmentError != nil {
                RollRecoveryNotice(viewModel: viewModel, onReturnHome: onReturnHome)
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

// Only presented after a failed operation; the normal shooting/reveal flow is unchanged.
struct RollRecoveryNotice: View {
    @ObservedObject var viewModel: RollViewModel
    var onReturnHome: (() -> Void)?

    var body: some View {
        NineDialogSurface {
            VStack(spacing: NineSpacing.large) {
                Text(viewModel.persistenceError ?? viewModel.developmentError ?? "Please try again.")
                    .font(NineType.body)
                    .foregroundStyle(.white.opacity(0.88))
                    .multilineTextAlignment(.center)
                NinePrimaryButton(title: "Try Again") {
                    if viewModel.persistenceError != nil {
                        Task { await viewModel.retryPersistence() }
                    } else {
                        viewModel.retryDevelopment()
                    }
                }
                .disabled(viewModel.isRetryingPersistence)
                if let onReturnHome {
                    NineSecondaryButton(title: "Return Home", action: onReturnHome)
                }
            }
        }
    }
}
