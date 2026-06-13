import SwiftUI
import UIKit

@MainActor
final class RollViewModel: ObservableObject {
    @Published private(set) var activeRoll: Roll?
    @Published private(set) var storedRolls: [Roll] = []
    @Published private(set) var resumableRoll: Roll?
    @Published private(set) var resumeState: RollResumeState?
    @Published private(set) var unavailableRollCount = 0
    @Published var statusMessage: String?
    @Published var isExporting = false

    private let store: RollStore
    private let blendEngine = BlendEngine()
    private var persistenceTask: Task<Void, Never>?

    init(store: RollStore = RollStore()) {
        self.store = store
        resumeState = nil
        print("[Nine] RollViewModel initialized")
    }

    func loadRolls(autoResume: Bool = false) async {
        print("[Nine] RollStore load started")
        do {
            let result = try await store.loadRolls()
            storedRolls = result.rolls
                .filter { $0.phase == .complete }
                .map(archiveReady)
            resumableRoll = result.rolls
                .filter(\.requiresCaptureInput)
                .sorted { $0.updatedAt > $1.updatedAt }
                .first
            resumeState = resumableRoll.map(RollResumeState.init)
            unavailableRollCount = result.unavailableRollCount
            print("[Nine] RollStore load completed · active roll found: \(resumableRoll != nil) · completed rolls: \(storedRolls.count) · unavailable: \(unavailableRollCount)")
            if result.unavailableRollCount > 0 {
                statusMessage = "\(result.unavailableRollCount) saved roll could not be restored."
            } else if result.repairedRollCount > 0 {
                statusMessage = "A saved roll was recovered to its last complete exposure."
            }
            if autoResume {
                _ = await resolveLaunchResumeRoll()
            }
        } catch {
            print("[Nine] RollStore load failed · \(error.localizedDescription)")
            resumableRoll = nil
            resumeState = nil
            statusMessage = error.localizedDescription
        }
    }

    func startRoll(mode: RollMode) async {
        print("[Nine] start roll requested · mode: \(mode.rawValue)")
        let createdAt = Date()
        let fallbackTitle = RollTitleGenerator.fallbackTitle(for: createdAt)
        let roll = Roll(createdAt: createdAt, mode: mode, title: fallbackTitle)
        activeRoll = roll
        resumableRoll = nil
        resumeState = RollResumeState(roll: roll)
        statusMessage = nil
        do {
            try await store.save(roll)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func continueRoll() {
        print("[Nine] continue roll requested · hydrated: \(resumableRoll != nil) · cached resume: \(resumeState != nil)")
        guard let roll = resumableRoll else {
            if let resumeState {
                Task { await hydrateAndContinueRoll(id: resumeState.id) }
            }
            return
        }
        guard roll.requiresCaptureInput else {
            resumableRoll = nil
            resumeState = nil
            return
        }
        let continuedRoll = squareNormalized(roll)
        activeRoll = continuedRoll
        statusMessage = nil
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard self.activeRoll?.id == continuedRoll.id else { return }
            self.resumableRoll = nil
            self.resumeState = nil
        }
    }

    @discardableResult
    func resolveLaunchResumeRoll() async -> Roll? {
        let token = ResumeRollCache.load()
        print("[Nine] resume token exists: \(token != nil)")
        if let token {
            print("[Nine] resume roll id: \(token.rollID.uuidString)")
        }

        guard let token else {
            activeRoll = nil
            resumableRoll = nil
            resumeState = nil
            print("[Nine] final launch destination: home")
            return nil
        }

        do {
            let roll = try await store.loadRoll(id: token.rollID)
            logLaunchResumeValidation(roll: roll, token: token)

            guard isValidResumeRoll(roll, resume: token), let roll else {
                ResumeRollCache.clear()
                activeRoll = nil
                resumableRoll = nil
                resumeState = nil
                print("[Nine] final launch destination: home")
                return nil
            }

            let resumedRoll = squareNormalized(roll)
            activeRoll = resumedRoll
            resumableRoll = nil
            resumeState = RollResumeState(roll: resumedRoll)
            print("[Nine] final launch destination: camera")
            return resumedRoll
        } catch {
            ResumeRollCache.clear()
            activeRoll = nil
            resumableRoll = nil
            resumeState = nil
            statusMessage = error.localizedDescription
            print("[Nine] loaded roll exists: false")
            print("[Nine] is valid resume: false")
            print("[Nine] final launch destination: home")
            return nil
        }
    }

    func discardResumableAndStart(mode: RollMode) async {
        do {
            if let roll = resumableRoll {
                try await store.discard(roll)
            } else if let id = resumeState?.id {
                try await store.discardRoll(id: id)
            }
            resumableRoll = nil
            resumeState = nil
            await startRoll(mode: mode)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func open(_ roll: Roll) {
        print("[Nine] open completed roll · \(roll.id.uuidString)")
        activeRoll = archiveReady(roll)
        statusMessage = nil
    }

    func renameRoll(id: UUID, to title: String) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        if var roll = activeRoll, roll.id == id {
            roll.rename(to: trimmedTitle)
            activeRoll = roll
            enqueuePersistence(for: roll)
        }

        if let index = storedRolls.firstIndex(where: { $0.id == id }) {
            var roll = storedRolls[index]
            roll.rename(to: trimmedTitle)
            storedRolls[index] = roll
            enqueuePersistence(for: roll)
        }

        if var roll = resumableRoll, roll.id == id {
            roll.rename(to: trimmedTitle)
            resumableRoll = roll
            resumeState = RollResumeState(roll: roll)
            enqueuePersistence(for: roll)
        }
    }

    func deleteStoredRolls(at offsets: IndexSet) {
        let rollsToDelete = offsets.compactMap { storedRolls[safe: $0] }
        guard !rollsToDelete.isEmpty else { return }

        storedRolls.remove(atOffsets: offsets)
        Task {
            do {
                for roll in rollsToDelete {
                    try await store.discard(roll)
                }
            } catch {
                statusMessage = error.localizedDescription
                await loadRolls()
            }
        }
    }

    func deleteStoredRoll(_ roll: Roll) {
        if activeRoll?.id == roll.id {
            activeRoll = nil
        }
        if resumableRoll?.id == roll.id {
            resumableRoll = nil
        }
        if resumeState?.id == roll.id {
            resumeState = nil
        }
        storedRolls.removeAll { $0.id == roll.id }
        Task {
            do {
                try await store.discard(roll)
            } catch {
                statusMessage = error.localizedDescription
                await loadRolls()
            }
        }
    }

    func returnHome() {
        if let activeRoll, activeRoll.requiresCaptureInput {
            resumableRoll = activeRoll
            resumeState = RollResumeState(roll: activeRoll)
        }
        activeRoll = nil
        statusMessage = nil
    }

    func recordCapture(_ image: UIImage) async throws -> CaptureMilestone {
        guard var roll = activeRoll else { throw RollError.captureUnavailable }
        guard let data = await encodedJPEGData(from: image) else {
            throw RollError.imageEncodingFailed
        }

        let frame = CapturedFrame(imageData: data)
        let milestone = try roll.append(frame)
        activeRoll = roll
        resumeState = roll.requiresCaptureInput ? RollResumeState(roll: roll) : nil
        enqueuePersistence(for: roll)

        if milestone == .secondPassComplete {
            Task {
                await self.flushPendingPersistence()
                await self.developCurrentRoll()
            }
        }
        return milestone
    }

    func exportContactSheet() async {
        guard let images = activeRoll?.blendedImages,
              let grid = GridRenderer.render(images: images) else { return }
        await saveToPhotos([grid], completionText: "Contact sheet saved.")
    }

    func exportAllFrames() async {
        guard let images = activeRoll?.blendedImages else { return }
        await saveToPhotos(images.map(GridRenderer.squareImage), completionText: "Nine individual frames saved.")
    }

    func exportFrame(at index: Int) async {
        guard let image = activeRoll?.blendedImages[safe: index] else { return }
        await saveToPhotos([GridRenderer.squareImage(image)], completionText: "Frame saved.")
    }

    func persistActiveRoll() async {
        guard var roll = activeRoll, roll.phase != .complete else { return }
        roll.touch()
        do {
            await flushPendingPersistence()
            try await store.save(roll)
            activeRoll = roll
            resumeState = roll.requiresCaptureInput ? RollResumeState(roll: roll) : nil
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func handleScenePhase(_ phase: ScenePhase) async {
        switch phase {
        case .inactive, .background:
            await persistActiveRoll()
        case .active:
            if activeRoll == nil {
                await loadRolls()
            }
        @unknown default:
            break
        }
    }

    private func developCurrentRoll() async {
        await flushPendingPersistence()
        guard var roll = activeRoll, roll.phase == .developing else { return }
        do {
            let images = try await blendEngine.develop(roll)
            let grid = GridRenderer.render(images: images)
            try roll.finishDevelopment(images: images, gridImage: grid)
            try await store.save(roll)
            let visibleRoll = archiveReady(roll)
            activeRoll = visibleRoll
            resumableRoll = nil
            resumeState = nil
            storedRolls.removeAll { $0.id == roll.id }
            storedRolls.insert(visibleRoll, at: 0)

            var output = images
            if let grid {
                output.append(grid)
            }
            await saveToPhotos(output, completionText: nil)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func saveToPhotos(_ images: [UIImage], completionText: String?) async {
        isExporting = true
        defer { isExporting = false }
        do {
            try await PhotoLibrarySaver.save(images: images)
            statusMessage = completionText
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func squareNormalized(_ roll: Roll) -> Roll {
        var squareRoll = roll
        squareRoll.blendedImages = roll.blendedImages.map(GridRenderer.squareImage)
        squareRoll.gridImage = roll.gridImage.map(GridRenderer.squareImage)
        return squareRoll
    }

    private func archiveReady(_ roll: Roll) -> Roll {
        var displayRoll = squareNormalized(roll)
        displayRoll.firstPassImages = []
        displayRoll.secondPassImages = []
        return displayRoll
    }

    private func logLaunchCandidate(_ roll: Roll?) {
        guard let roll else {
            print("[Nine] Launch candidate roll: nil · phase: nil · firstPass count: 0 · secondPass count: 0 · blended count: 0 · shouldResumeToCamera: false")
            return
        }

        print(
            """
            [Nine] Launch candidate roll: \(roll.id.uuidString) · phase: \(roll.phase.rawValue) · firstPass count: \(roll.firstPassImages.count) · secondPass count: \(roll.secondPassImages.count) · blended count: \(roll.blendedImages.count) · grid: \(roll.gridImage == nil ? "none" : "present") · shouldResumeToCamera: \(shouldResumeToCamera(roll))
            """
        )
    }

    private func logLaunchResumeValidation(roll: Roll?, token: ResumeRollState) {
        print("[Nine] loaded roll exists: \(roll != nil)")
        guard let roll else {
            print("[Nine] roll phase: nil")
            print("[Nine] first pass count: 0")
            print("[Nine] second pass count: 0")
            print("[Nine] blended count: 0")
            print("[Nine] is valid resume: false")
            return
        }

        print("[Nine] roll phase: \(roll.phase.rawValue)")
        print("[Nine] first pass count: \(roll.firstPassImages.count)")
        print("[Nine] second pass count: \(roll.secondPassImages.count)")
        print("[Nine] blended count: \(roll.blendedImages.count)")
        print("[Nine] is valid resume: \(isValidResumeRoll(roll, resume: token))")
    }

    private func hydrateAndContinueRoll(id: UUID) async {
        print("[Nine] hydrate active roll started · \(id.uuidString)")
        do {
            let result = try await store.loadRolls()
            guard let roll = result.rolls.first(where: { $0.id == id && $0.requiresCaptureInput }) else {
                resumeState = nil
                statusMessage = "The saved roll could not be restored."
                print("[Nine] hydrate active roll failed · roll not found")
                return
            }
            resumableRoll = roll
            print("[Nine] hydrate active roll completed · phase: \(roll.phase.rawValue) · frame count: \(roll.capturedFrameCount)")
            continueRoll()
        } catch {
            print("[Nine] hydrate active roll failed · \(error.localizedDescription)")
            resumeState = nil
            statusMessage = error.localizedDescription
        }
    }

    private func enqueuePersistence(for roll: Roll) {
        let previousTask = persistenceTask
        persistenceTask = Task { [weak self] in
            await previousTask?.value
            guard let self else { return }
            do {
                try await self.store.save(roll)
            } catch {
                await MainActor.run {
                    self.statusMessage = error.localizedDescription
                }
            }
        }
    }

    private func flushPendingPersistence() async {
        await persistenceTask?.value
        persistenceTask = nil
    }

    private nonisolated func encodedJPEGData(from image: UIImage) async -> Data? {
        await Task.detached(priority: .userInitiated) {
            image.jpegData(compressionQuality: 0.98)
        }.value
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
