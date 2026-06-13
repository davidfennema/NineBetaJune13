import SwiftUI

struct HomeView: View {
    @ObservedObject var viewModel: RollViewModel
    @State private var selectedMode: RollMode = .freeform
    @State private var showsAbout = false

    var body: some View {
        let _ = print("[Nine] HomeView body rendered · activeRoll exists: \(viewModel.activeRoll != nil) · resumeState exists: \(viewModel.resumeState != nil)")

        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 22) {
                    NineBrandMark()
                        .frame(width: 120, height: 120)
                        .padding(.top, 62)
                        .padding(.bottom, 4)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            showsAbout = true
                        }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityLabel("About Nine")

                    modeSelection

                    primaryActions

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
        .sheet(isPresented: $showsAbout) {
            NineAboutView()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    private var primaryActions: some View {
        VStack(spacing: 12) {
            Button {
                Task { await viewModel.startRoll(mode: selectedMode) }
            } label: {
                Text("Start New Roll")
                    .font(AfterimageType.primaryAction)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private var modeSelection: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 14, alignment: .leading), count: 2),
                alignment: .leading,
                spacing: 14
            ) {
                ForEach(RollMode.allCases) { mode in
                    Button {
                        selectedMode = mode
                    } label: {
                        ModeRadioRow(
                            title: mode.title,
                            isSelected: selectedMode == mode
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var archiveList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Completed Rolls")
                .font(AfterimageType.metadata)
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.55))

            List {
                ForEach(viewModel.storedRolls) { roll in
                    ArchiveRollRow(roll: roll)
                    .onTapGesture {
                        viewModel.open(roll)
                    }
                    .listRowInsets(EdgeInsets(top: 5, leading: 0, bottom: 5, trailing: 0))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            viewModel.deleteStoredRoll(roll)
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

private struct NineAboutView: View {
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            Text("Nine is a double-exposure camera.\n\nShoot nine frames, then re-load the roll and shoot nine more.\n\nEnjoy the unexpected.")
                .font(AfterimageType.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 300)
            .padding(.horizontal, 28)
        }
    }
}

private struct ModeRadioRow: View {
    let title: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
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
                .lineLimit(1)
                .minimumScaleFactor(0.82)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
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
