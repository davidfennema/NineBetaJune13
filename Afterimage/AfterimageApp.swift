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
    @AppStorage("nine.hasSeenIntro") private var hasSeenIntro = false
    @State private var launchDestination: LaunchDestination = .resolving
    @State private var routeDirection: RouteDirection = .forward
    @State private var isReturningFromReveal = false
    private let routeAnimation = Animation.smooth(duration: 0.21, extraBounce: 0)

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                switch launchDestination {
                case .resolving:
                    Color.black.ignoresSafeArea()
                case .intro:
                    IntroView(onBegin: completeIntro)
                case .home:
                    if showsCompletedRollScreen {
                        revealHomeContainer(width: geometry.size.width)
                    } else if showsDevelopingScreen {
                        resolvedScreen
                    } else {
                        homeCameraContainer(width: geometry.size.width)
                    }
                case .camera(let roll):
                    if shouldResumeToCamera(roll) {
                        homeCameraContainer(width: geometry.size.width)
                    } else if showsCompletedRollScreen {
                        revealHomeContainer(width: geometry.size.width)
                    } else if showsDevelopingScreen {
                        resolvedScreen
                    } else {
                        HomeView(
                            viewModel: viewModel,
                            onContinueRoll: showCamera,
                            onStartRoll: startRoll,
                            onOpenRoll: openStoredRoll
                        )
                    }
                case .reveal:
                    if showsCompletedRollScreen {
                        revealHomeContainer(width: geometry.size.width)
                    } else {
                        HomeView(
                            viewModel: viewModel,
                            onContinueRoll: showCamera,
                            onStartRoll: startRoll,
                            onOpenRoll: openStoredRoll
                        )
                    }
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
            } else if !hasSeenIntro {
                launchDestination = .intro
            } else {
                launchDestination = .home
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            Task {
                await viewModel.handleScenePhase(newPhase)
            }
        }
        .onChange(of: viewModel.activeRoll?.phase) { _, newPhase in
            guard newPhase == .complete,
                  let roll = viewModel.activeRoll else { return }
            routeDirection = .forward
            withAnimation(routeAnimation) {
                launchDestination = .reveal(roll)
            }
        }
    }

    private func homeCameraContainer(width: CGFloat) -> some View {
        ZStack {
            HomeView(
                viewModel: viewModel,
                onContinueRoll: showCamera,
                onStartRoll: startRoll,
                onOpenRoll: openStoredRoll
            )
            .offset(x: homeOffset(width: width))
            .allowsHitTesting(isShowingHome)

            if hasCameraRoute {
                CameraView(viewModel: viewModel, onReturnHome: showHome)
                    .offset(x: cameraOffset(width: width))
                    .allowsHitTesting(isShowingCamera)
            }
        }
        .animation(routeAnimation, value: routeKey)
    }

    private func revealHomeContainer(width: CGFloat) -> some View {
        ZStack {
            HomeView(
                viewModel: viewModel,
                onContinueRoll: showCamera,
                onStartRoll: startRoll,
                onOpenRoll: openStoredRoll
            )
            .offset(x: isShowingHome ? 0 : -width)
            .allowsHitTesting(isShowingHome && !isReturningFromReveal)

            RevealView(viewModel: viewModel, onReturnHome: showHomeFromReveal)
                .offset(x: isShowingHome ? width : 0)
                .allowsHitTesting(!isShowingHome)
        }
        .animation(routeAnimation, value: routeKey)
    }

    @ViewBuilder
    private var resolvedScreen: some View {
        if let roll = viewModel.activeRoll {
            switch roll.phase {
            case .firstPass, .secondPass:
                if shouldResumeToCamera(roll) {
                    CameraView(viewModel: viewModel, onReturnHome: showHome)
                } else {
                    HomeView(
                        viewModel: viewModel,
                        onContinueRoll: showCamera,
                        onStartRoll: startRoll,
                        onOpenRoll: openStoredRoll
                    )
                }
            case .developing:
                DevelopingView()
            case .complete:
                RevealView(viewModel: viewModel, onReturnHome: showHomeFromReveal)
            }
        } else {
            HomeView(
                viewModel: viewModel,
                onContinueRoll: showCamera,
                onStartRoll: startRoll,
                onOpenRoll: openStoredRoll
            )
        }
    }

    private func showHomeFromReveal() {
        isReturningFromReveal = true
        routeDirection = .back
        withAnimation(routeAnimation) {
            launchDestination = .home
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(230))
            guard case .home = launchDestination else { return }
            viewModel.returnHome()
            isReturningFromReveal = false
        }
    }

    private func showHome() {
        routeDirection = .back
        withAnimation(routeAnimation) {
            launchDestination = .home
        }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(230))
            guard case .home = launchDestination else { return }
            viewModel.parkActiveRollForLibrary()
        }
    }

    private func showCamera() {
        viewModel.continueRoll()
        if let roll = viewModel.activeRoll, shouldResumeToCamera(roll) {
            routeDirection = .forward
            withAnimation(routeAnimation) {
                launchDestination = .camera(roll)
            }
        }
    }

    private func openStoredRoll(_ roll: Roll) {
        viewModel.open(roll)
        guard viewModel.activeRoll?.phase == .complete else { return }
        routeDirection = .forward
        withAnimation(routeAnimation) {
            launchDestination = .reveal(roll)
        }
    }

    private func completeIntro() {
        hasSeenIntro = true
        routeDirection = .forward
        withAnimation(routeAnimation) {
            launchDestination = .home
        }
    }

    private func startRoll(mode: RollMode, discardingCurrentRoll: Bool) async {
        if discardingCurrentRoll {
            await viewModel.discardResumableAndStart(mode: mode)
        } else {
            await viewModel.startRoll(mode: mode)
        }
        showCamera()
    }

    private var showsCompletedRollScreen: Bool {
        viewModel.activeRoll?.phase == .complete
    }

    private var showsDevelopingScreen: Bool {
        viewModel.activeRoll?.phase == .developing
    }

    private var hasCameraRoute: Bool {
        if let roll = viewModel.activeRoll, shouldResumeToCamera(roll) {
            return true
        }
        if case .camera(let roll) = launchDestination {
            return shouldResumeToCamera(roll)
        }
        return false
    }

    private var isShowingHome: Bool {
        if case .home = launchDestination { return true }
        return false
    }

    private var isShowingCamera: Bool {
        if case .camera = launchDestination { return true }
        return false
    }

    private var routeKey: String {
        "\(routeName)-\(routeDirection)"
    }

    private var routeName: String {
        switch launchDestination {
        case .resolving:
            return "resolving"
        case .intro:
            return "intro"
        case .home:
            return "home"
        case .camera:
            return "camera"
        case .reveal:
            return "reveal"
        }
    }

    private func homeOffset(width: CGFloat) -> CGFloat {
        guard !isShowingHome else { return 0 }
        return routeDirection == .forward ? -width : width
    }

    private func cameraOffset(width: CGFloat) -> CGFloat {
        guard !isShowingCamera else { return 0 }
        return routeDirection == .back ? width : -width
    }
}

private enum LaunchDestination {
    case resolving
    case intro
    case home
    case camera(Roll)
    case reveal(Roll)
}

private enum RouteDirection {
    case forward
    case back
}
