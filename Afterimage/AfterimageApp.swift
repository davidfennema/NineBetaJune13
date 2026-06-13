import SwiftUI

@main
struct NineApp: App {
    @StateObject private var rollViewModel = RollViewModel()

    init() {
        print("[Nine] App entry loaded")
    }

    var body: some Scene {
        WindowGroup {
            RootView(viewModel: rollViewModel)
                .preferredColorScheme(.dark)
        }
    }
}

struct RootView: View {
    @ObservedObject var viewModel: RollViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var launchDestination: LaunchDestination = .resolving

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch launchDestination {
            case .resolving:
                Color.black.ignoresSafeArea()
            case .home:
                resolvedScreen
            case .camera(let roll):
                if shouldResumeToCamera(roll) {
                    resolvedScreen
                } else {
                    HomeView(viewModel: viewModel)
                }
            }
        }
        .onAppear {
            print("[Nine] Root view loaded · activeRoll exists: \(viewModel.activeRoll != nil)")
        }
        .task {
            guard case .resolving = launchDestination else { return }
            await viewModel.loadRolls()
            if let roll = await viewModel.resolveLaunchResumeRoll() {
                launchDestination = .camera(roll)
            } else {
                launchDestination = .home
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            Task {
                await viewModel.handleScenePhase(newPhase)
            }
        }
    }

    @ViewBuilder
    private var resolvedScreen: some View {
        if let roll = viewModel.activeRoll {
            switch roll.phase {
            case .firstPass, .secondPass:
                if shouldResumeToCamera(roll) {
                    CameraView(viewModel: viewModel)
                } else {
                    HomeView(viewModel: viewModel)
                }
            case .developing:
                DevelopingView()
            case .complete:
                RevealView(viewModel: viewModel)
            }
        } else {
            HomeView(viewModel: viewModel)
        }
    }
}

private enum LaunchDestination {
    case resolving
    case home
    case camera(Roll)
}
