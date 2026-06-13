import SwiftUI

struct ExposureCounterView: View {
    enum CounterSize {
        case viewfinder
        case compact
        case expanded

        var windowSize: CGSize {
            switch self {
            case .viewfinder:
                CGSize(width: 58, height: 24)
            case .compact:
                CGSize(width: 62, height: 62)
            case .expanded:
                CGSize(width: 76, height: 76)
            }
        }

        var fontSize: CGFloat {
            switch self {
            case .viewfinder: 15
            case .compact: 18
            case .expanded: 23
            }
        }

        var cornerRadius: CGFloat {
            switch self {
            case .viewfinder: 0
            case .compact: 31
            case .expanded: 38
            }
        }
    }

    let frameNumber: Int
    let phase: RollPhase
    let size: CounterSize
    let animatesChanges: Bool
    let tint: Color
    let showsWindow: Bool

    @State private var visibleLabel: String
    @State private var outgoingLabel: String?
    @State private var wheelOffset: CGFloat = 0
    @State private var animationTask: Task<Void, Never>?

    init(
        frameNumber: Int,
        phase: RollPhase,
        size: CounterSize = .compact,
        animatesChanges: Bool = true,
        tint: Color = .white,
        showsWindow: Bool = true
    ) {
        let label = Self.label(for: frameNumber, phase: phase)
        self.frameNumber = frameNumber
        self.phase = phase
        self.size = size
        self.animatesChanges = animatesChanges
        self.tint = tint
        self.showsWindow = showsWindow
        _visibleLabel = State(initialValue: label)
    }

    var body: some View {
        let metrics = size.windowSize

        ZStack {
            if showsWindow {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                tint.opacity(0.13),
                                tint.opacity(0.065)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay {
                        Circle()
                            .stroke(tint.opacity(0.22), lineWidth: 1)
                    }
                    .overlay(alignment: .top) {
                        Circle()
                            .stroke(tint.opacity(0.18), lineWidth: 1)
                            .blur(radius: 0.2)
                            .offset(y: 0.5)
                    }
                }

            ZStack {
                if let outgoingLabel {
                    counterText(outgoingLabel)
                        .offset(y: wheelOffset)
                }

                counterText(visibleLabel)
                    .offset(y: outgoingLabel == nil ? 0 : wheelOffset + metrics.height)
            }
            .frame(width: metrics.width, height: metrics.height)
            .clipped()
            .mask(RoundedRectangle(cornerRadius: size.cornerRadius - 1, style: .continuous))
        }
        .frame(width: metrics.width, height: metrics.height)
        .shadow(color: tint.opacity(size == .viewfinder ? 0.32 : 0), radius: size == .viewfinder ? 5 : 0)
        .shadow(color: .black.opacity(showsWindow ? 0.24 : 0), radius: 10, y: 7)
        .onChange(of: counterToken) { _, _ in
            advanceCounter()
        }
        .onDisappear {
            animationTask?.cancel()
        }
        .accessibilityLabel(accessibilityText)
    }

    private var counterToken: String {
        "\(frameNumber)"
    }

    private var accessibilityText: String {
        "Frame \(frameNumber)"
    }

    private func counterText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: size.fontSize, weight: .semibold, design: .monospaced))
            .monospacedDigit()
            .tracking(1.4)
            .foregroundStyle(tint.opacity(0.94))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .contentTransition(.identity)
    }

    private func advanceCounter() {
        let nextLabel = Self.label(for: frameNumber, phase: phase)
        guard nextLabel != visibleLabel else { return }

        animationTask?.cancel()

        if !animatesChanges {
            outgoingLabel = nil
            wheelOffset = 0
            visibleLabel = nextLabel
            return
        }

        outgoingLabel = visibleLabel
        visibleLabel = nextLabel
        wheelOffset = 0

        withAnimation(AfterimageMotion.quick) {
            wheelOffset = -size.windowSize.height
        }

        animationTask = Task {
            try? await Task.sleep(for: .milliseconds(165))
            guard !Task.isCancelled else { return }
            outgoingLabel = nil
            wheelOffset = 0
        }
    }

    private static func label(for frameNumber: Int, phase: RollPhase) -> String {
        let clampedFrame = min(max(frameNumber, 1), Roll.frameCount)
        return String(format: "%02d", clampedFrame)
    }
}
