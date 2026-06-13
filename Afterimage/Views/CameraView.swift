import SwiftUI
import UIKit

struct CameraView: View {
    @ObservedObject var viewModel: RollViewModel
    @StateObject private var camera = CameraManager()
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
    @AppStorage("afterimage.didShowFocusLockHint") private var didShowFocusLockHint = false
    @AppStorage("afterimage.didShowPinchHint") private var didShowPinchHint = false

    private var roll: Roll? { viewModel.activeRoll }
    private var previewSaturation: Double {
        switch roll?.mode {
        case .blackAndWhite:
            return 0
        case .desaturated:
            return 0.42
        default:
            return 1
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let squareSide = min(geometry.size.width - (AfterimageLayout.margin * 2), geometry.size.height * 0.54)

            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    header
                        .padding(.top, geometry.safeAreaInsets.top + 14)
                        .padding(.horizontal, AfterimageLayout.margin)

                    Spacer(minLength: 22)

                    squarePreview(side: squareSide)

                    Spacer(minLength: 20)

                    shutter
                        .padding(.top, 22)
                        .padding(.bottom, max(geometry.safeAreaInsets.bottom, 22))
                }

                if camera.authorizationDenied {
                    permissionNotice
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
            PreviewView(session: camera.session)
                .frame(width: side, height: side)
                .saturation(previewSaturation)

            if let ghost = roll?.correspondingFirstExposure {
                Image(uiImage: ghost)
                    .resizable()
                    .scaledToFill()
                    .frame(width: side, height: side)
                    .blur(radius: 0.7)
                    .saturation(previewSaturation)
                    .opacity(0.58)
                    .blendMode(.screen)
                    .allowsHitTesting(false)
                    .transition(AfterimageMotion.subtleTransition)
            }

            if showsBlackout {
                Color.black
                    .transition(.opacity)
            }

            if let focusPoint {
                FocusReticle(isLocked: camera.isHoldFocusLocked)
                    .position(focusPoint)
                    .transition(AfterimageMotion.subtleTransition)
            }

            ViewfinderInfoOverlay(
                zoomFactor: camera.zoomFactor,
                exposureBias: camera.exposureBias,
                isFocusLocked: camera.isHoldFocusLocked
            )
            .frame(maxHeight: .infinity, alignment: .bottom)

            if let contextualHint {
                ContextualCameraHint(text: contextualHint)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 44)
                    .transition(AfterimageMotion.toastTransition)
            }
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
                    camera.focus(
                        at: CGPoint(
                            x: value.location.x / side,
                            y: value.location.y / side
                        )
                    )
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
                HStack(alignment: .center, spacing: AfterimageLayout.counterLockupSpacing) {
                    ExposureCounterView(
                        frameNumber: displayedFrameNumber,
                        phase: roll?.phase ?? .firstPass,
                        size: .compact
                    )

                    Text(phaseCaption)
                        .font(AfterimageType.caption)
                        .tracking(1.35)
                        .foregroundStyle(.white.opacity(0.38))
                }

                Spacer()

                ProgressGrid(count: roll?.capturedFrameCount ?? 0)
            }
        }
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
            .animation(AfterimageMotion.quick, value: isCapturing)
        }
        .disabled(!camera.isReady || isCapturing || showsTransition)
        .buttonStyle(AfterimagePressButtonStyle())
    }

    private var permissionNotice: some View {
        VStack(spacing: 12) {
            Text("Camera access is required")
                .font(AfterimageType.rollTitle)
            Text("Allow access in Settings to expose a roll.")
                .font(AfterimageType.body)
                .foregroundStyle(.white.opacity(0.56))
        }
        .foregroundStyle(.white)
        .padding(28)
        .background(.black.opacity(0.9), in: RoundedRectangle(cornerRadius: AfterimageLayout.controlCornerRadius, style: .continuous))
    }

    private var transitionOverlay: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Text(transitionText)
                .font(AfterimageType.rollTitle)
                .foregroundStyle(.white.opacity(0.92))
                .transition(AfterimageMotion.subtleTransition)
        }
        .transition(AfterimageMotion.screenTransition)
    }

    private var displayedFrameNumber: Int {
        min((roll?.capturedFrameCount ?? 0) + 1, Roll.frameCount)
    }

    private var phaseCaption: String {
        roll?.phase == .secondPass ? "SECOND PASS" : "FIRST PASS"
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
                camera.beginHoldFocusLock(
                    at: CGPoint(x: point.x / side, y: point.y / side)
                )
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
        withAnimation(AfterimageMotion.quick) {
            focusPoint = point
        }
        focusFeedbackTask = Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            withAnimation(AfterimageMotion.standard) { focusPoint = nil }
        }
    }

    private func showLockedFeedback(at point: CGPoint) {
        focusFeedbackTask?.cancel()
        withAnimation(AfterimageMotion.quick) {
            focusPoint = point
        }
        focusFeedbackTask = Task {
            try? await Task.sleep(for: .milliseconds(780))
            guard !Task.isCancelled else { return }
            withAnimation(AfterimageMotion.standard) {
                focusPoint = nil
            }
        }
    }

    private func showContextualHint(_ text: String) {
        hintTask?.cancel()
        withAnimation(AfterimageMotion.quick) {
            contextualHint = text
        }
        hintTask = Task {
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            withAnimation(AfterimageMotion.standard) {
                contextualHint = nil
            }
        }
    }

    private func exposeFrame() {
        guard !isCapturing else { return }
        isCapturing = true
        triggerShutterFeedback()
        blinkShutter()
        Task {
            do {
                let image = try await camera.capturePhoto()
                let milestone = try await viewModel.recordCapture(image)
                camera.resetFocusLockAfterCapture()

                if milestone == .firstPassComplete {
                    await showSecondPassTransition()
                }
            } catch {
                camera.resetFocusLockAfterCapture()
                showsBlackout = false
                viewModel.statusMessage = error.localizedDescription
            }
            isCapturing = false
        }
    }

    private func triggerShutterFeedback() {
        let feedback = UIImpactFeedbackGenerator(style: .light)
        feedback.prepare()
        feedback.impactOccurred(intensity: 0.82)
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
        withAnimation(AfterimageMotion.quick) {
            showsBlackout = true
        }
        Task {
            try? await Task.sleep(for: .milliseconds(95))
            withAnimation(AfterimageMotion.quick) {
                showsBlackout = false
            }
        }
    }

    private func showSecondPassTransition() async {
        withAnimation(AfterimageMotion.reveal) {
            showsTransition = true
            transitionText = "First exposure complete."
        }
        try? await Task.sleep(for: .seconds(1.35))
        withAnimation(AfterimageMotion.reveal) {
            transitionText = "Begin second pass."
        }
        try? await Task.sleep(for: .seconds(1.25))
        showsBlackout = false
        withAnimation(AfterimageMotion.longReveal) { showsTransition = false }
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
        .animation(AfterimageMotion.standard, value: count)
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

private struct ContextualCameraHint: View {
    let text: String

    var body: some View {
        Text(text)
            .font(AfterimageType.caption)
            .tracking(1.1)
            .multilineTextAlignment(.center)
            .foregroundStyle(.white.opacity(0.72))
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(.black.opacity(0.48), in: Capsule())
    }
}
