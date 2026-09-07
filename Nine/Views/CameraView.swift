import SwiftUI
import UIKit

struct CameraView: View {
    @ObservedObject var viewModel: RollViewModel
    var onReturnHome: (() -> Void)?
    @StateObject private var camera: CameraManager
    @Environment(\.scenePhase) private var scenePhase

    @State private var isCapturing = false
    @State private var showsBlackout = false
    @State private var showsTransition = false
    @State private var transitionText = ""
    @State private var focusPoint: CGPoint?
    @State private var zoomOrigin: CGFloat = 1
    @State private var touchOrigin: CGPoint?
    @State private var isHoldingFocusLock = false
    @State private var suppressNextTap = false
    @State private var focusFeedbackTask: Task<Void, Never>?
    @State private var exposureDragOrigin: Float?
    @State private var lastExposureHapticStep: Int?
    @State private var contextualHint: String?
    @State private var hintTask: Task<Void, Never>?
    @State private var showsCameraHelp = false
    @State private var showsFirstPassDecision = false
    @AppStorage("nine.didShowFocusLockHint") private var didShowFocusLockHint = false
    @AppStorage("nine.didShowPinchHint") private var didShowPinchHint = false

    init(viewModel: RollViewModel, onReturnHome: (() -> Void)? = nil) {
        self.viewModel = viewModel
        self.onReturnHome = onReturnHome
        _camera = StateObject(
            wrappedValue: CameraManager(
                initialPosition: Self.initialCameraPosition(for: viewModel.activeRoll)
            )
        )
    }

    private var roll: Roll? { viewModel.activeRoll }
    private var previewSaturation: Double {
        roll?.mode.previewSaturation ?? 1
    }

    private var previewContrast: Double {
        roll?.mode.previewContrast ?? 1
    }

    var body: some View {
        GeometryReader { geometry in
            let imageStage = NineLayout.imageStage(in: geometry)
            let shutterY = geometry.size.height - max(geometry.safeAreaInsets.bottom, 22) - NineLayout.shutterBottomOffset
            let belowPreviewSwipeHeight = max(52, min(72, shutterY - imageStage.bottom - 96))
            let underPreviewControlY = imageStage.bottom + NineLayout.imageStageControlOffset
            let belowPreviewSwipeY = imageStage.bottom + NineLayout.imageStageSwipeOffset + belowPreviewSwipeHeight / 2

            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    header
                        .padding(.top, geometry.safeAreaInsets.top + NineLayout.headerTopSpacing)
                        .padding(.horizontal, NineLayout.horizontalScreenMargin)

                    Spacer()
                }
                .zIndex(3)

                squarePreview(side: imageStage.side)
                    .position(x: imageStage.centerX, y: imageStage.centerY)
                    .zIndex(1)

                shutter
                    .position(
                        x: geometry.size.width / 2,
                        y: shutterY
                    )
                    .zIndex(2)

                underPreviewControlRow(width: imageStage.side)
                    .position(x: imageStage.centerX, y: underPreviewControlY)
                    .zIndex(3)

                belowPreviewSwipeZone(width: imageStage.side, height: belowPreviewSwipeHeight)
                    .position(x: imageStage.centerX, y: belowPreviewSwipeY)
                    .zIndex(3)

                edgeSwipeZone(height: geometry.size.height)
                    .position(x: 12, y: geometry.size.height / 2)
                    .zIndex(3)

                NineCloseButton {
                    onReturnHome?()
                }
                .position(
                    x: NineLayout.margin,
                    y: NineLayout.closeControlY(in: geometry)
                )
                .zIndex(5)

                if camera.authorizationDenied {
                    permissionNotice
                }
                if showsCameraHelp, !showsFirstPassDecision {
                    Color.black
                        .opacity(0.001)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(NineMotion.standard) {
                                showsCameraHelp = false
                            }
                        }
                        .zIndex(6)

                    NineFloatingNotification(
                        text: "Pinch to zoom.\n\nSwipe to adjust exposure.\n\nLong-tap for AF lock."
                    )
                    .position(x: imageStage.centerX, y: imageStage.centerY)
                    .transition(NineMotion.toastTransition)
                    .zIndex(7)
                }
                if let contextualHint, !showsFirstPassDecision, !showsCameraHelp {
                    NineFloatingNotification(text: contextualHint)
                        .position(x: imageStage.centerX, y: imageStage.centerY)
                        .allowsHitTesting(false)
                        .transition(NineMotion.toastTransition)
                        .zIndex(6)
                }
                if showsFirstPassDecision {
                    Color.black
                        .opacity(0.001)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .zIndex(6)

                    firstPassDecisionOverlay
                        .position(x: imageStage.centerX, y: imageStage.centerY)
                        .transition(NineMotion.screenTransition)
                        .zIndex(7)
                }
                if showsTransition {
                    transitionOverlay
                }
            }
        }
        .task {
            if scenePhase == .active {
                await camera.start()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task { await camera.start() }
            } else {
                camera.stop()
            }
        }
        .onDisappear { camera.stop() }
    }

    private func squarePreview(side: CGFloat) -> some View {
        ZStack {
            PreviewView(session: camera.session, isMirrored: camera.isPreviewMirrored)
                .frame(width: side, height: side)
                .saturation(previewSaturation)
                .contrast(previewContrast)

            if let ghost = roll?.correspondingFirstExposure {
                Image(uiImage: ghost)
                    .resizable()
                    .scaledToFill()
                    .frame(width: side, height: side)
                    .blur(radius: 0.7)
                    .saturation(previewSaturation)
                    .contrast(previewContrast)
                    .opacity(0.58)
                    .blendMode(.screen)
                    .allowsHitTesting(false)
                    .transition(NineMotion.subtleTransition)
            }

            CompositionGrid()
                .frame(width: side, height: side)
                .allowsHitTesting(false)

            if showsBlackout {
                Color.black
                    .transition(.opacity)
            }

            if let focusPoint {
                FocusReticle(isLocked: camera.isHoldFocusLocked)
                    .position(focusPoint)
                    .transition(NineMotion.subtleTransition)
            }

            ViewfinderInfoOverlay(
                zoomFactor: camera.zoomFactor,
                exposureBias: camera.exposureBias,
                isFocusLocked: camera.isHoldFocusLocked
            )
            .frame(maxHeight: .infinity, alignment: .bottom)

        }
        .frame(width: side, height: side)
        .clipped()
        .overlay {
            Rectangle()
                .stroke(.white.opacity(0.16), lineWidth: 1)
        }
        .contentShape(Rectangle())
        .gesture(
            SpatialTapGesture()
                .onEnded { value in
                    guard !showsBlackout else { return }
                    guard !suppressNextTap else {
                        suppressNextTap = false
                        return
                    }
                    showFocusReticle(at: value.location)
                    camera.focus(at: normalizedCameraPoint(from: value.location, side: side))
                }
        )
        .simultaneousGesture(exposureDragGesture(side: side))
        .simultaneousGesture(touchTrackingGesture())
        .simultaneousGesture(focusLockGesture(side: side))
        .simultaneousGesture(
            MagnifyGesture()
                .onChanged { value in
                    if !didShowPinchHint {
                        didShowPinchHint = true
                        showContextualHint("Pinch to zoom")
                    }
                    camera.setZoomFactor(zoomOrigin * value.magnification)
                }
                .onEnded { _ in
                    zoomOrigin = camera.zoomFactor
                }
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                HStack(alignment: .center, spacing: NineLayout.counterLockupSpacing) {
                    ExposureCounterView(
                        frameNumber: displayedFrameNumber,
                        phase: displayedCapturePhase,
                        size: .compact
                    )

                    Text(phaseCaption)
                        .font(NineType.instrumentCaption)
                        .tracking(1.35)
                        .foregroundStyle(.white.opacity(0.38))
                }

                Spacer()

                ProgressGrid(count: roll?.capturedFrameCount ?? 0)
                    .padding(.trailing, 1)
            }
        }
    }

    private var cameraSwitchButton: some View {
        Button {
            print("[Nine] Camera switch tapped")
            camera.switchCamera()
        } label: {
            Image(systemName: "camera.rotate")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white.opacity(camera.canSwitchCamera ? 0.46 : 0.16))
                .frame(width: 38, height: 38)
                .contentShape(Rectangle())
        }
        .buttonStyle(NinePressButtonStyle())
        .disabled(isCapturing || showsBlackout || showsTransition || camera.isSwitchingCamera || !camera.isReady)
        .accessibilityLabel(camera.cameraPosition == .front ? "Switch to rear camera" : "Switch to front camera")
    }

    private var cameraHelpButton: some View {
        Button {
            showsCameraHelp = true
        } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 18.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.36))
                .frame(width: 38, height: 38)
                .contentShape(Rectangle())
        }
        .buttonStyle(NinePressButtonStyle())
        .disabled(showsTransition)
        .accessibilityLabel("Camera help")
    }

    private func underPreviewControlRow(width: CGFloat) -> some View {
        HStack(alignment: .center, spacing: 10) {
            cameraSwitchButton
                .frame(width: 44, alignment: .leading)

            Spacer(minLength: 10)

            rollStyleLabel
                .frame(maxWidth: width - 116, alignment: .center)

            Spacer(minLength: 10)

            cameraHelpButton
                .frame(width: 44, alignment: .trailing)
        }
        .frame(width: width, height: 40)
    }

    private var rollStyleLabel: some View {
        Text(roll?.mode.title ?? "Natural")
            .font(NineType.caption)
            .tracking(0.45)
            .foregroundStyle(.white.opacity(0.36))
            .lineLimit(1)
            .allowsHitTesting(false)
    }

    private func belowPreviewSwipeZone(width: CGFloat, height: CGFloat) -> some View {
        Color.clear
            .frame(width: width, height: height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 24)
                    .onEnded { value in
                        guard isIntentionalHomeSwipe(value.translation, minimumDistance: 72) else { return }
                        onReturnHome?()
                    }
            )
            .accessibilityLabel("Swipe right to return to Library")
    }

    private func edgeSwipeZone(height: CGFloat) -> some View {
        Color.clear
            .frame(width: 24, height: height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 18)
                    .onEnded { value in
                        guard value.startLocation.x <= 24 else { return }
                        guard isIntentionalHomeSwipe(value.translation, minimumDistance: 84) else { return }
                        onReturnHome?()
                    }
            )
            .accessibilityLabel("Swipe from left edge to return to Library")
    }

    private func isIntentionalHomeSwipe(_ translation: CGSize, minimumDistance: CGFloat) -> Bool {
        guard !showsTransition else { return false }
        guard translation.width > minimumDistance else { return false }
        return abs(translation.width) > abs(translation.height) * 1.55
    }

    private var shutter: some View {
        Button {
            exposeFrame()
        } label: {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.85), lineWidth: 2)
                    .frame(width: 76, height: 76)
                Circle()
                    .fill(.white.opacity(isCapturing ? 0.42 : 0.92))
                    .frame(width: 62, height: 62)
                    .scaleEffect(isCapturing ? 0.91 : 1)
            }
            .animation(NineMotion.quick, value: isCapturing)
        }
        .disabled(!camera.isReady || isCapturing || showsTransition)
        .buttonStyle(NinePressButtonStyle())
        .accessibilityLabel("Expose frame \(displayedFrameNumber) of \(Roll.frameCount)")
        .accessibilityHint(phaseCaption.capitalized)
    }

    private var permissionNotice: some View {
        VStack(spacing: 12) {
            Text("Camera access is required")
                .font(NineType.rollTitle)
            Text("Allow access in Settings to expose a roll.")
                .font(NineType.body)
                .foregroundStyle(.white.opacity(0.56))
        }
        .foregroundStyle(.white)
        .padding(28)
        .background(.black.opacity(NineOpacity.floatingOverlayBackground), in: RoundedRectangle(cornerRadius: NineLayout.cardDialogCornerRadius, style: .continuous))
    }

    private var transitionOverlay: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Text(transitionText)
                .font(NineType.rollTitle)
                .foregroundStyle(.white.opacity(0.92))
                .transition(NineMotion.subtleTransition)
        }
        .transition(NineMotion.screenTransition)
    }

    private var displayedFrameNumber: Int {
        min((roll?.capturedFrameCount ?? 0) + 1, Roll.frameCount)
    }

    private var displayedCapturePhase: RollPhase {
        guard let roll else { return .firstPass }
        if roll.phase == .developing, roll.secondPassImages.count == Roll.frameCount {
            return .secondPass
        }
        return roll.phase
    }

    private var phaseCaption: String {
        displayedCapturePhase == .secondPass ? "SECOND PASS" : "FIRST PASS"
    }

    private func touchTrackingGesture() -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if touchOrigin == nil {
                    touchOrigin = value.startLocation
                }
            }
            .onEnded { _ in
                touchOrigin = nil
            }
    }

    private func exposureDragGesture(side: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard !showsBlackout, !isHoldingFocusLock else { return }
                guard abs(value.translation.width) > abs(value.translation.height) * 1.45 else { return }
                guard abs(value.translation.width) > 16 else { return }

                suppressNextTap = true
                let origin = exposureDragOrigin ?? camera.exposureBias
                exposureDragOrigin = origin

                let adjustment = Float(value.translation.width / side) * 4
                let nextBias = origin + adjustment
                camera.setExposureBias(nextBias)
                triggerExposureTickIfNeeded(for: camera.exposureBias)
            }
            .onEnded { _ in
                exposureDragOrigin = nil
                lastExposureHapticStep = nil
            }
    }

    private func focusLockGesture(side: CGFloat) -> some Gesture {
        LongPressGesture(minimumDuration: 0.38, maximumDistance: 18)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                guard case .second(true, _) = value, !isHoldingFocusLock else { return }
                let point = touchOrigin ?? CGPoint(x: side / 2, y: side / 2)
                isHoldingFocusLock = true
                suppressNextTap = true
                showLockedFeedback(at: point)
                if camera.beginHoldFocusLock(at: normalizedCameraPoint(from: point, side: side)) {
                    triggerFocusLockFeedback()
                }
                if !didShowFocusLockHint {
                    didShowFocusLockHint = true
                    showContextualHint("AF LOCK\nDrag left or right to adjust exposure")
                }
            }
            .onEnded { _ in
                guard isHoldingFocusLock else { return }
                isHoldingFocusLock = false
            }
    }

    private func showFocusReticle(at point: CGPoint) {
        focusFeedbackTask?.cancel()
        withAnimation(NineMotion.quick) {
            focusPoint = point
        }
        focusFeedbackTask = Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            withAnimation(NineMotion.standard) { focusPoint = nil }
        }
    }

    private func showLockedFeedback(at point: CGPoint) {
        focusFeedbackTask?.cancel()
        withAnimation(NineMotion.quick) {
            focusPoint = point
        }
        focusFeedbackTask = Task {
            try? await Task.sleep(for: .milliseconds(780))
            guard !Task.isCancelled else { return }
            withAnimation(NineMotion.standard) {
                focusPoint = nil
            }
        }
    }

    private func showContextualHint(_ text: String) {
        hintTask?.cancel()
        withAnimation(NineMotion.quick) {
            contextualHint = text
        }
        hintTask = Task {
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            withAnimation(NineMotion.standard) {
                contextualHint = nil
            }
        }
    }

    private func exposeFrame() {
        guard !isCapturing else { return }
        guard viewModel.activeRoll?.requiresCaptureInput == true else { return }
        isCapturing = true
        triggerShutterFeedback()
        blinkShutter()
        Task {
            do {
                let image = try await camera.capturePhoto()
                let milestone = try await viewModel.recordCapture(
                    image,
                    metadata: ["cameraPosition": camera.cameraPosition.rawValue]
                )
                camera.resetFocusLockAfterCapture()

                if milestone == .firstPassComplete {
                    withAnimation(NineMotion.standard) {
                        showsFirstPassDecision = true
                    }
                }
            } catch {
                camera.resetFocusLockAfterCapture()
                showsBlackout = false
                viewModel.statusMessage = error.localizedDescription
            }
            isCapturing = false
        }
    }

    private var firstPassDecisionOverlay: some View {
        NineDialogSurface {
            VStack(spacing: NineSpacing.large) {
                VStack(spacing: NineSpacing.medium) {
                    Text("First Pass Complete.")
                        .font(NineType.rollTitle)
                        .foregroundStyle(.white.opacity(0.88))

                    Text("Save for later?\n\nYou can keep up to 3 unfinished rolls.")
                        .font(NineType.body)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.58))
                        .lineSpacing(3)
                }

                VStack(spacing: NineSpacing.medium) {
                    NineSecondaryButton(
                        title: "Save First Pass",
                        isDisabled: !viewModel.canSaveFirstPassForLater
                    ) {
                        Task {
                            if await viewModel.saveFirstPassForLater() {
                                withAnimation(NineMotion.standard) {
                                    showsFirstPassDecision = false
                                }
                                onReturnHome?()
                            }
                        }
                    }

                    NinePrimaryButton(title: "Begin Second Pass") {
                        withAnimation(NineMotion.standard) {
                            showsFirstPassDecision = false
                        }
                        Task {
                            await viewModel.beginSecondPassForActiveRoll()
                            await showSecondPassTransition()
                        }
                    }
                }
            }
        }
    }

    private func triggerShutterFeedback() {
        let feedback = UIImpactFeedbackGenerator(style: .light)
        feedback.prepare()
        feedback.impactOccurred(intensity: 0.82)
    }

    private func triggerFocusLockFeedback() {
        let feedback = UIImpactFeedbackGenerator(style: .light)
        feedback.prepare()
        feedback.impactOccurred(intensity: 0.58)
    }

    private func triggerExposureTickIfNeeded(for bias: Float) {
        let step = Int((bias * 2).rounded())
        guard step != lastExposureHapticStep else { return }
        lastExposureHapticStep = step
        let feedback = UISelectionFeedbackGenerator()
        feedback.prepare()
        feedback.selectionChanged()
    }

    private func blinkShutter() {
        withAnimation(NineMotion.quick) {
            showsBlackout = true
        }
        Task {
            try? await Task.sleep(for: .milliseconds(95))
            withAnimation(NineMotion.quick) {
                showsBlackout = false
            }
        }
    }

    private func showSecondPassTransition() async {
        withAnimation(NineMotion.reveal) {
            showsTransition = true
            transitionText = "First exposure complete."
        }
        try? await Task.sleep(for: .seconds(1.35))
        withAnimation(NineMotion.reveal) {
            transitionText = "Begin second pass."
        }
        try? await Task.sleep(for: .seconds(1.25))
        showsBlackout = false
        withAnimation(NineMotion.longReveal) { showsTransition = false }
    }

    private func normalizedCameraPoint(from point: CGPoint, side: CGFloat) -> CGPoint {
        let normalizedX = min(max(point.x / side, 0), 1)
        let normalizedY = min(max(point.y / side, 0), 1)
        return CGPoint(
            x: camera.isPreviewMirrored ? 1 - normalizedX : normalizedX,
            y: normalizedY
        )
    }

    private static func initialCameraPosition(for roll: Roll?) -> NineCameraPosition {
        guard let roll else { return .back }
        let latestFrame = roll.secondPassImages.last ?? roll.firstPassImages.last
        guard let rawPosition = latestFrame?.metadata?["cameraPosition"],
              let position = NineCameraPosition(rawValue: rawPosition) else {
            return .back
        }
        return position
    }
}

private struct ProgressGrid: View {
    let count: Int

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(7), spacing: 3), count: 3), spacing: 3) {
            ForEach(0..<Roll.frameCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(.white.opacity(index < count ? 0.42 : 0.085))
                    .overlay {
                        RoundedRectangle(cornerRadius: 1.5)
                            .stroke(.white.opacity(0.14), lineWidth: 0.5)
                    }
                    .frame(width: 7, height: 7)
            }
        }
        .frame(width: 28)
        .animation(NineMotion.standard, value: count)
    }
}

private struct FocusReticle: View {
    let isLocked: Bool

    var body: some View {
        Circle()
            .stroke(.white.opacity(isLocked ? 0.84 : 0.62), lineWidth: 1)
            .frame(width: 58, height: 58)
            .overlay {
                Circle()
                    .fill(.white.opacity(0.7))
                    .frame(width: 3, height: 3)
            }
    }
}

private struct CompositionGrid: View {
    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height

            Path { path in
                for index in 1...2 {
                    let x = width * CGFloat(index) / 3
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: height))

                    let y = height * CGFloat(index) / 3
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: width, y: y))
                }
            }
            .stroke(.white.opacity(0.18), lineWidth: 0.6)
        }
    }
}
