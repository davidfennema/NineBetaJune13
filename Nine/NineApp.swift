import SwiftUI

@main
struct NineApp: App {
    @StateObject private var rollViewModel = RollViewModel()
    @StateObject private var unlockStore = UnlockStore()

    init() {
        print("[Nine] App entry loaded")
    }

    var body: some Scene {
        WindowGroup {
            RootView(viewModel: rollViewModel, unlockStore: unlockStore)
                .preferredColorScheme(.dark)
        }
    }
}

struct RootView: View {
    @ObservedObject var viewModel: RollViewModel
    @ObservedObject var unlockStore: UnlockStore
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("nine.hasSeenIntro") private var hasSeenIntro = false
    @State private var launchDestination: LaunchDestination = .resolving
    @State private var routeDirection: RouteDirection = .forward
    @State private var isReturningFromReveal = false
    @State private var showsUnlockPrompt = false
    @State private var pendingStartRequest: PendingStartRequest?
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
                            onOpenSavedRoll: openSavedRoll,
                            onOpenRoll: openStoredRoll,
                            onShowUnlockPromptForTesting: showUnlockPromptForTesting
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
                            onOpenSavedRoll: openSavedRoll,
                            onOpenRoll: openStoredRoll,
                            onShowUnlockPromptForTesting: showUnlockPromptForTesting
                        )
                    }
                }

                if showsUnlockPrompt {
                    unlockPrompt
                        .transition(NineMotion.screenTransition)
                        .zIndex(10)
                }
            }
        }
        .onAppear {
            print("[Nine] Root view loaded · activeRoll exists: \(viewModel.activeRoll != nil)")
        }
        .task {
            guard case .resolving = launchDestination else { return }
            await unlockStore.configure()
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
                onOpenSavedRoll: openSavedRoll,
                onOpenRoll: openStoredRoll,
                onShowUnlockPromptForTesting: showUnlockPromptForTesting
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
                onOpenRoll: openStoredRoll,
                onShowUnlockPromptForTesting: showUnlockPromptForTesting
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
                        onOpenSavedRoll: openSavedRoll,
                        onOpenRoll: openStoredRoll,
                        onShowUnlockPromptForTesting: showUnlockPromptForTesting
                    )
                }
            case .awaitingSecondPass:
                HomeView(
                    viewModel: viewModel,
                    onContinueRoll: showCamera,
                    onStartRoll: startRoll,
                    onOpenSavedRoll: openSavedRoll,
                    onOpenRoll: openStoredRoll,
                    onShowUnlockPromptForTesting: showUnlockPromptForTesting
                )
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
                onOpenSavedRoll: openSavedRoll,
                onOpenRoll: openStoredRoll,
                onShowUnlockPromptForTesting: showUnlockPromptForTesting
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
        viewModel.parkActiveRollForLibrary()
        routeDirection = .back
        withAnimation(routeAnimation) {
            launchDestination = .home
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

    private func openSavedRoll(_ roll: Roll) async {
        await viewModel.resumeSavedFirstPass(roll)
        showCamera()
    }

    private func completeIntro() {
        hasSeenIntro = true
        routeDirection = .forward
        withAnimation(routeAnimation) {
            launchDestination = .home
        }
    }

    private func showUnlockPromptForTesting() {
        pendingStartRequest = nil
        withAnimation(NineMotion.standard) {
            showsUnlockPrompt = true
        }
    }

    private func startRoll(mode: RollMode, discardingCurrentRoll: Bool) async {
        guard unlockStore.canBeginNewRoll(hasCompletedFreeRoll: viewModel.hasCompletedFreeRoll) else {
            pendingStartRequest = PendingStartRequest(mode: mode, discardingCurrentRoll: discardingCurrentRoll)
            withAnimation(NineMotion.standard) {
                showsUnlockPrompt = true
            }
            return
        }

        await beginRoll(mode: mode, discardingCurrentRoll: discardingCurrentRoll)
    }

    private func beginRoll(mode: RollMode, discardingCurrentRoll: Bool) async {
        if discardingCurrentRoll {
            await viewModel.discardResumableAndStart(mode: mode)
        } else {
            await viewModel.startRoll(mode: mode)
        }
        showCamera()
    }

    private var unlockPrompt: some View {
        ZStack {
            Color.black
                .opacity(NineOpacity.dialogScrim)
                .ignoresSafeArea()
                .contentShape(Rectangle())

            NineDialogSurface {
                VStack(spacing: NineSpacing.large) {
                    VStack(spacing: NineSpacing.medium) {
                        Text("Your first roll is complete.")
                            .font(NineType.rollTitle)
                            .foregroundStyle(.white.opacity(0.88))

                        Text("Unlock Nine to keep shooting.")
                            .font(NineType.body)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white.opacity(0.58))
                            .lineSpacing(3)
                    }

                    VStack(spacing: NineSpacing.medium) {
                        NinePrimaryButton(title: unlockButtonTitle, isDisabled: unlockStore.isLoading) {
                            Task {
                                await unlockStore.purchaseUnlock()
                                await continuePendingStartIfUnlocked()
                            }
                        }

                        NineSecondaryButton(title: "Restore Purchase", isDisabled: unlockStore.isLoading) {
                            Task {
                                await unlockStore.restorePurchases()
                                await continuePendingStartIfUnlocked()
                            }
                        }

                        NineSecondaryButton(title: "Not Now", isDisabled: unlockStore.isLoading) {
                            pendingStartRequest = nil
                            withAnimation(NineMotion.standard) {
                                showsUnlockPrompt = false
                            }
                        }
                    }

                    if let message = unlockStore.statusMessage {
                        Text(message)
                            .font(NineType.body)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white.opacity(NineOpacity.dimmed))
                    }
                }
            }
            .padding(.horizontal, NineLayout.horizontalScreenMargin)
        }
    }

    private var unlockButtonTitle: String {
        if unlockStore.isLoading {
            return "Unlocking..."
        }
        let price = unlockStore.unlockProduct?.displayPrice ?? "$7.99"
        return "Unlock Nine · \(price)"
    }

    private func continuePendingStartIfUnlocked() async {
        guard unlockStore.isUnlocked else { return }
        let request = pendingStartRequest
        pendingStartRequest = nil
        withAnimation(NineMotion.standard) {
            showsUnlockPrompt = false
        }
        if let request {
            await beginRoll(mode: request.mode, discardingCurrentRoll: request.discardingCurrentRoll)
        }
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

private struct PendingStartRequest {
    let mode: RollMode
    let discardingCurrentRoll: Bool
}
