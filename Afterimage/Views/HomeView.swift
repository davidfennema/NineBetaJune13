import SwiftUI

struct HomeView: View {
    @ObservedObject var viewModel: RollViewModel
    var onContinueRoll: (() -> Void)?
    var onStartRoll: ((RollMode, Bool) async -> Void)?
    var onOpenSavedRoll: ((Roll) async -> Void)?
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
                VStack(spacing: AfterimageSpacing.large) {
                    NineBrandMark()
                        .frame(width: 188, height: 188)
                        .padding(.top, AfterimageSpacing.extraLarge * 2)
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

                    if !viewModel.savedFirstPassRolls.isEmpty {
                        savedRollsList
                    }

                    if !viewModel.storedRolls.isEmpty {
                        archiveList
                    }

                    if let statusMessage = viewModel.statusMessage {
                        Text(statusMessage)
                            .font(AfterimageType.body)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white.opacity(AfterimageOpacity.dimmed))
                            .padding(.horizontal, AfterimageLayout.horizontalScreenMargin)
                    }

                    Spacer(minLength: 60)
                }
                .padding(.horizontal, AfterimageLayout.horizontalScreenMargin)
                .frame(maxWidth: .infinity)
            }

            if showsStartOverConfirmation {
                ZStack {
                    Color.black
                        .opacity(AfterimageOpacity.dialogScrim)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())

                    startOverConfirmationDialog
                        .padding(.horizontal, AfterimageLayout.horizontalScreenMargin)
                }
                .transition(AfterimageMotion.screenTransition)
                .zIndex(2)
            }

            if showsReplacementStylePicker {
                ZStack {
                    Color.black
                        .opacity(AfterimageOpacity.dialogScrim)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())

                    replacementStyleDialog
                        .padding(.horizontal, AfterimageLayout.horizontalScreenMargin)
                }
                .transition(AfterimageMotion.screenTransition)
                .zIndex(3)
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
    }

    private var createSection: some View {
        VStack(spacing: AfterimageSpacing.large) {
            modeSelection
            startNewRollButton
        }
        .padding(.top, AfterimageLayout.decisionGroupOpticalOffset)
    }

    private var resumeSection: some View {
        VStack(spacing: AfterimageSpacing.medium) {
            AfterimageSecondaryButton(title: "Continue Roll") {
                onContinueRoll?()
            }
        }
    }

    private var startNewRollButton: some View {
        VStack(spacing: AfterimageSpacing.medium) {
            if viewModel.hasInProgressRoll {
                AfterimageSecondaryButton(title: "Start New Roll") {
                    withAnimation(AfterimageMotion.standard) {
                        showsStartOverConfirmation = true
                    }
                }
            } else {
                AfterimagePrimaryButton(title: "Start New Roll") {
                    Task {
                        await onStartRoll?(selectedMode, false)
                    }
                }
            }
        }
    }

    private var startOverConfirmationDialog: some View {
        AfterimageDialogSurface {
            VStack(spacing: AfterimageSpacing.large) {
                VStack(spacing: AfterimageSpacing.medium) {
                    Text("Discard unfinished first pass?")
                        .font(AfterimageType.rollTitle)
                        .foregroundStyle(.white.opacity(0.88))

                    Text("This roll hasn't completed its first pass yet, so it can't be saved for later.")
                        .font(AfterimageType.body)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.58))
                        .lineSpacing(3)
                }

                VStack(spacing: AfterimageSpacing.medium) {
                    AfterimageSecondaryButton(title: "Cancel") {
                        withAnimation(AfterimageMotion.standard) {
                            showsStartOverConfirmation = false
                        }
                    }

                    AfterimagePrimaryButton(title: "Discard Roll and Start Over") {
                        replacementMode = activeRollMode ?? selectedMode
                        withAnimation(AfterimageMotion.standard) {
                            showsStartOverConfirmation = false
                            showsReplacementStylePicker = true
                        }
                    }
                }
            }
        }
    }

    private var replacementStyleDialog: some View {
        AfterimageDialogSurface {
            VStack(spacing: AfterimageSpacing.large) {
                Text("Choose Style")
                    .font(AfterimageType.rollTitle)
                    .foregroundStyle(.white.opacity(0.86))

                replacementModeSelection

                AfterimagePrimaryButton(title: "Begin Roll") {
                    selectedMode = replacementMode
                    withAnimation(AfterimageMotion.standard) {
                        showsReplacementStylePicker = false
                    }
                    Task {
                        await onStartRoll?(replacementMode, true)
                    }
                }
            }
        }
    }

    private var modeSelection: some View {
        modeSelection(selectedMode: $selectedMode)
    }

    private var replacementModeSelection: some View {
        modeSelection(selectedMode: $replacementMode)
    }

    private func modeSelection(selectedMode: Binding<RollMode>) -> some View {
        VStack(alignment: .center, spacing: AfterimageSpacing.small) {
            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(118), spacing: AfterimageSpacing.large, alignment: .center), count: 2),
                alignment: .center,
                spacing: AfterimageSpacing.medium
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

    private var savedRollsList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Saved Rolls")
                .font(AfterimageType.metadata)
                .tracking(1.2)
                .foregroundStyle(.white.opacity(AfterimageOpacity.dimmed))

            List {
                ForEach(viewModel.savedFirstPassRolls) { roll in
                    Button {
                        guard !showsStartOverConfirmation else { return }
                        Task {
                            await onOpenSavedRoll?(roll)
                        }
                    } label: {
                        SavedFirstPassRollRow(roll: roll)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .listRowInsets(EdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            withAnimation(AfterimageMotion.standard) {
                                viewModel.deleteSavedFirstPassRoll(roll)
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
            .frame(height: CGFloat(viewModel.savedFirstPassRolls.count) * 86)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var archiveList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Completed Rolls")
                .font(AfterimageType.metadata)
                .tracking(1.2)
                .foregroundStyle(.white.opacity(AfterimageOpacity.dimmed))

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

private struct SavedFirstPassRollRow: View {
    let roll: Roll

    var body: some View {
        HStack(spacing: 12) {
            firstPassPreview

            VStack(alignment: .leading, spacing: 5) {
                Text(roll.title)
                    .font(AfterimageType.archiveTitle)
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(savedRollStatus)
                    .font(AfterimageType.rollListStatus)
                    .foregroundStyle(.white.opacity(0.48))

                Text(roll.mode.title)
                    .font(AfterimageType.rollListStyle)
                    .tracking(1.0)
                    .foregroundStyle(.white.opacity(0.34))
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .afterimageCardSurface()
        .contentShape(Rectangle())
    }

    private var savedRollStatus: String {
        guard roll.phase == .secondPass else {
            return "Ready for second pass"
        }
        return "Second pass \(roll.secondPassImages.count)/\(Roll.frameCount)"
    }

    private var firstPassPreview: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 3), spacing: 2) {
            ForEach(0..<Roll.frameCount, id: \.self) { index in
                if let frame = roll.firstPassImages[safe: index],
                   let image = FirstPassThumbnailRenderer.thumbnail(
                    for: frame,
                    rollID: roll.id,
                    mode: roll.mode,
                    side: 56
                   ) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .clipped()
                } else {
                    Rectangle()
                        .fill(.white.opacity(0.08))
                }
            }
        }
        .padding(3)
        .frame(width: 56, height: 56)
        .background(.white.opacity(0.035))
        .overlay {
            Rectangle()
                .stroke(.white.opacity(0.1), lineWidth: 1)
        }
        .clipped()
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
                    .font(AfterimageType.rollListStatus)
                    .foregroundStyle(.white.opacity(0.48))

                Text(roll.mode.title)
                    .font(AfterimageType.rollListStyle)
                    .tracking(1.0)
                    .foregroundStyle(.white.opacity(0.34))
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
        .afterimageCardSurface()
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

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
