import SwiftUI

struct RevealView: View {
    @ObservedObject var viewModel: RollViewModel
    @AppStorage("afterimage.shareAttributionEnabled") private var shareAttributionEnabled = true
    @State private var visibleFrameCount = 0
    @State private var pageIndex = 0
    @State private var shareItem: SharePreviewItem?
    @State private var isPreparingShare = false

    private var images: [UIImage] {
        viewModel.activeRoll?.blendedImages ?? []
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 20) {
                revealHeader
                rollPager
                navigationIndicator
                persistentActions
                Spacer(minLength: 0)
            }
            .padding(.horizontal, AfterimageLayout.margin)
            .padding(.top, AfterimageLayout.headerTopSpacing)
            .padding(.bottom, 22)

            if let message = viewModel.statusMessage {
                toast(message)
                    .transition(AfterimageMotion.toastTransition)
                    .zIndex(3)
            }
        }
        .sheet(item: $shareItem) { item in
            ActivityView(activityItems: [item.image])
                .ignoresSafeArea()
        }
        .task(id: viewModel.activeRoll?.id) {
            pageIndex = 0
            visibleFrameCount = 0
            guard !images.isEmpty else { return }
            for index in 1...images.count {
                try? await Task.sleep(for: .milliseconds(index == 1 ? 150 : 78))
                withAnimation(AfterimageMotion.reveal) {
                    visibleFrameCount = index
                }
            }
        }
    }

    private var revealHeader: some View {
        HStack(alignment: .top) {
            AfterimageBackButton(action: viewModel.returnHome)

            Spacer()
            VStack(spacing: 7) {
                if let roll = viewModel.activeRoll {
                    EditableRollTitleView(
                        title: roll.title,
                        style: .reveal,
                        alignment: .center
                    ) { title in
                        viewModel.renameRoll(id: roll.id, to: title)
                    }
                }
                Text(viewModel.activeRoll?.mode.title ?? "")
                    .font(AfterimageType.metadata)
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.42))
            }
            Spacer()
            Color.clear.frame(width: AfterimageLayout.backControlSize, height: AfterimageLayout.backControlSize)
        }
        .foregroundStyle(.white.opacity(0.92))
    }

    private var rollPager: some View {
        TabView(selection: $pageIndex) {
            contactSheet
                .padding(.horizontal, 2)
                .tag(0)

            ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                ZoomableImage(image: image)
                    .padding(.horizontal, 4)
                    .tag(index + 1)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(maxWidth: .infinity)
        .aspectRatio(1, contentMode: .fit)
    }

    private var contactSheet: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 3), spacing: 5) {
            ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .aspectRatio(1, contentMode: .fit)
                    .clipped()
                    .opacity(index < visibleFrameCount ? 1 : 0)
                    .scaleEffect(index < visibleFrameCount ? 1 : 0.985)
                    .offset(y: index < visibleFrameCount ? 0 : 6)
            }
        }
        .background(.black)
        .padding(4)
        .overlay {
            Rectangle().stroke(.white.opacity(0.08), lineWidth: 1)
        }
    }

    private var navigationIndicator: some View {
        HStack(spacing: 12) {
            Text("‹")
                .opacity(pageIndex > 0 ? 1 : 0)

            Text(pageIndex == 0 ? "Contact Sheet" : "\(pageIndex)/\(images.count)")
                .font(AfterimageType.metadata)
                .tracking(1.1)
                .foregroundStyle(.white.opacity(0.48))
                .contentTransition(.opacity)

            Text("›")
                .opacity(pageIndex < images.count ? 1 : 0)
        }
        .font(.system(size: 17, weight: .medium, design: .serif))
        .foregroundStyle(.white.opacity(0.52))
        .frame(height: 18)
        .allowsHitTesting(false)
        .contentTransition(.opacity)
        .animation(AfterimageMotion.quick, value: pageIndex)
    }

    private var persistentActions: some View {
        AfterimagePrimaryButton(title: isPreparingShare ? "Preparing" : "Share", isDisabled: viewModel.isExporting || isPreparingShare || images.isEmpty) {
            prepareCurrentShare()
        }
        .padding(.top, 2)
    }

    private func toast(_ message: String) -> some View {
        VStack {
            Spacer()
            Text(message)
                .font(AfterimageType.body)
                .foregroundStyle(.white.opacity(0.84))
                .padding(.horizontal, 18)
                .padding(.vertical, 11)
                .background(.white.opacity(0.1), in: Capsule())
                .padding(.bottom, 12)
        }
        .onTapGesture { viewModel.statusMessage = nil }
    }

    private func prepareCurrentShare() {
        guard let roll = viewModel.activeRoll else { return }

        if pageIndex == 0 {
            prepareShare(kind: .grid, roll: roll) {
                ShareRenderer.grid(for: roll, includesAttribution: shareAttributionEnabled)
            }
        } else {
            let frameIndex = pageIndex - 1
            guard images.indices.contains(frameIndex) else { return }
            let image = images[frameIndex]
            prepareShare(kind: .frame, roll: roll) {
                ShareRenderer.frame(image, includesAttribution: shareAttributionEnabled)
            }
        }
    }

    private func prepareShare(kind: ShareExportKind, roll: Roll, render: @escaping () -> UIImage?) {
        withAnimation(AfterimageMotion.quick) {
            isPreparingShare = true
        }
        Task {
            let image = await Task.detached(priority: .userInitiated) {
                render()
            }.value
            withAnimation(AfterimageMotion.quick) {
                isPreparingShare = false
            }
            guard let image else {
                viewModel.statusMessage = "The share image could not be prepared."
                return
            }
            shareItem = SharePreviewItem(image: image, title: roll.title, kind: kind)
        }
    }
}

private struct ZoomableImage: View {
    let image: UIImage
    @State private var scale: CGFloat = 1
    @GestureState private var magnification: CGFloat = 1

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .scaleEffect(scale * magnification)
            .gesture(
                MagnifyGesture()
                    .updating($magnification) { value, state, _ in
                        state = value.magnification
                    }
                    .onEnded { value in
                        scale = min(max(scale * value.magnification, 1), 5)
                    }
            )
    }
}
