import SwiftUI

struct HomeView: View {
    @ObservedObject var viewModel: RollViewModel
    var onContinueRoll: (() -> Void)?
    var onStartRoll: ((RollMode, Bool) async -> Void)?
    var onOpenRoll: ((Roll) -> Void)?
    @State private var selectedMode: RollMode = .freeform
    @State private var replacementMode: RollMode = .freeform
    @State private var showsAbout = false
    @State private var showsStartOverConfirmation = false
    @State private var showsReplacementStylePicker = false

    var body: some View {
        let _ = print("[Nine] HomeView body rendered · activeRoll exists: \(viewModel.activeRoll != nil) · resumeState exists: \(viewModel.resumeState != nil)")

        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    NineBrandMark()
                        .frame(width: 144, height: 144)
                        .padding(.top, 68)
                        .padding(.bottom, 12)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            showsAbout = true
                        }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityLabel("About Nine")

                    if viewModel.hasInProgressRoll {
                        resumeSection
                        startNewRollButton
                    } else {
                        createSection
                    }

                    if !viewModel.storedRolls.isEmpty {
                        archiveList
                    }

                    if let statusMessage = viewModel.statusMessage {
                        Text(statusMessage)
                            .font(AfterimageType.body)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white.opacity(0.55))
                            .padding(.horizontal, 24)
                    }

                    Spacer(minLength: 60)
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity)
            }
        }
        .onAppear {
            print("[Nine] HomeView appeared")
        }
        .fullScreenCover(isPresented: $showsAbout) {
            IntroView {
                showsAbout = false
            }
        }
        .sheet(isPresented: $showsReplacementStylePicker) {
            replacementStyleSheet
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .alert("Start New Roll?", isPresented: $showsStartOverConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Start Over", role: .destructive) {
                replacementMode = activeRollMode ?? selectedMode
                showsReplacementStylePicker = true
            }
        } message: {
            Text("Your current roll is not complete.\n\nStarting a new roll will discard it.")
        }
    }

    private var createSection: some View {
        VStack(spacing: 14) {
            modeSelection
            startNewRollButton
        }
    }

    private var resumeSection: some View {
        VStack(spacing: 12) {
            Button {
                onContinueRoll?()
            } label: {
                Text("Continue Roll")
                    .font(AfterimageType.primaryAction)
                .foregroundStyle(.white.opacity(0.84))
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(.white.opacity(0.13), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var startNewRollButton: some View {
        VStack(spacing: 12) {
            Button {
                if viewModel.hasInProgressRoll {
                    showsStartOverConfirmation = true
                } else {
                    Task {
                        await onStartRoll?(selectedMode, false)
                    }
                }
            } label: {
                Text("Start New Roll")
                    .font(AfterimageType.primaryAction)
                    .foregroundStyle(viewModel.hasInProgressRoll ? .white.opacity(0.76) : .black.opacity(0.92))
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(
                        viewModel.hasInProgressRoll ? .white.opacity(0.065) : .white.opacity(0.92),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                    .overlay {
                        if viewModel.hasInProgressRoll {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(.white.opacity(0.12), lineWidth: 1)
                        }
                    }
            }
            .buttonStyle(.plain)
        }
    }

    private var replacementStyleSheet: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 24) {
                Text("Choose Style")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(.white.opacity(0.86))

                replacementModeSelection

                Button {
                    selectedMode = replacementMode
                    showsReplacementStylePicker = false
                    Task {
                        await onStartRoll?(replacementMode, true)
                    }
                } label: {
                    Text("Begin Roll")
                        .font(AfterimageType.primaryAction)
                        .foregroundStyle(.black.opacity(0.92))
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
        }
    }

    private var modeSelection: some View {
        modeSelection(selectedMode: $selectedMode)
    }

    private var replacementModeSelection: some View {
        modeSelection(selectedMode: $replacementMode)
    }

    private func modeSelection(selectedMode: Binding<RollMode>) -> some View {
        VStack(alignment: .center, spacing: 10) {
            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(118), spacing: 18, alignment: .center), count: 2),
                alignment: .center,
                spacing: 16
            ) {
                ForEach(RollMode.allCases) { mode in
                    Button {
                        selectedMode.wrappedValue = mode
                    } label: {
                        ModeRadioRow(
                            title: mode.title,
                            isSelected: selectedMode.wrappedValue == mode
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var activeRollMode: RollMode? {
        viewModel.activeRoll?.mode
            ?? viewModel.resumableRoll?.mode
            ?? viewModel.resumeState?.mode
    }

    private var archiveList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Completed Rolls")
                .font(AfterimageType.metadata)
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.55))

            List {
                ForEach(viewModel.storedRolls) { roll in
                    Button {
                        guard !showsStartOverConfirmation else { return }
                        if let onOpenRoll {
                            onOpenRoll(roll)
                        } else {
                            viewModel.open(roll)
                        }
                    } label: {
                        ArchiveRollRow(roll: roll)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .listRowInsets(EdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            withAnimation(AfterimageMotion.standard) {
                                viewModel.deleteStoredRoll(roll)
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDisabled(true)
            .frame(height: CGFloat(viewModel.storedRolls.count) * 86)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ModeRadioRow: View {
    let title: String
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 7) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(isSelected ? 0.9 : 0.36), lineWidth: 1.4)
                    .frame(width: 18, height: 18)

                if isSelected {
                    Circle()
                        .fill(.white.opacity(0.9))
                        .frame(width: 8, height: 8)
                }
            }
            .frame(width: 22, height: 22)

            Text(title)
                .font(AfterimageType.body)
                .foregroundStyle(.white.opacity(isSelected ? 0.96 : 0.72))
                .multilineTextAlignment(.center)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .frame(width: 118, alignment: .center)
        .frame(minHeight: 48, alignment: .center)
        .contentShape(Rectangle())
    }
}

private struct NineBrandMark: View {
    var body: some View {
        Image("NineBrandMark")
            .resizable()
            .scaledToFit()
        .accessibilityHidden(true)
    }
}

private struct ArchiveRollRow: View {
    let roll: Roll

    var body: some View {
        HStack(spacing: 12) {
            contactSheetPreview

            VStack(alignment: .leading, spacing: 5) {
                Text(roll.title)
                    .font(AfterimageType.archiveTitle)
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(roll.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .font(AfterimageType.body)
                    .foregroundStyle(.white.opacity(0.5))

                Text(roll.mode.title)
                    .font(AfterimageType.caption)
                    .tracking(0.8)
                    .foregroundStyle(.white.opacity(0.38))
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var contactSheetPreview: some View {
        if let image = roll.gridImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 56, height: 56)
                .clipped()
                .overlay {
                    Rectangle()
                        .stroke(.white.opacity(0.14), lineWidth: 1)
                }
        } else {
            MiniContactSheetPlaceholder()
                .frame(width: 56, height: 56)
        }
    }
}

private struct MiniContactSheetPlaceholder: View {
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3), spacing: 2) {
            ForEach(0..<Roll.frameCount, id: \.self) { _ in
                Rectangle()
                    .fill(.white.opacity(0.08))
            }
        }
        .padding(3)
        .background(.white.opacity(0.035))
        .overlay {
            Rectangle()
                .stroke(.white.opacity(0.1), lineWidth: 1)
        }
    }
}
