import SwiftUI
import UIKit

@MainActor
final class RollViewModel: ObservableObject {
    static let savedFirstPassLimit = 3

    @Published private(set) var activeRoll: Roll?
    @Published private(set) var storedRolls: [Roll] = []
    @Published private(set) var savedFirstPassRolls: [Roll] = []
    @Published private(set) var resumableRoll: Roll?
    @Published private(set) var resumeState: RollResumeState?
    @Published private(set) var unavailableRollCount = 0
    @Published var statusMessage: String?
    @Published private(set) var savedOverlayMessage: String?
    @Published var isExporting = false

    private let store: RollStore
    private let blendEngine = BlendEngine()
    @Published private(set) var persistenceError: String?
    @Published private var developmentErrors: [UUID: String] = [:]
    @Published private(set) var isRetryingPersistence = false
    @Published private(set) var isSavingFirstPass = false

    private var persistenceTask: Task<Bool, Never>?
    private var persistenceSequence = 0
    private var pendingSnapshots: [UUID: Roll] = [:]
    private var pendingSequences: [UUID: Int] = [:]
    private var failedSaveIDs: Set<UUID> = []
    private var deletedRollIDs: Set<UUID> = []
    private var developingRollIDs: Set<UUID> = []
    private var completedPendingSave: [UUID: Roll] = [:]
    private var captureIDs: Set<UUID> = []
    private var stateVersion = 0
    private var isStartingRoll = false
    private var isReplacingRoll = false
    private let photoSaver: ([UIImage]) async throws -> Void

    var developmentError: String? {
        activeRoll.flatMap { developmentErrors[$0.id] }
    }

    init(store: RollStore = RollStore(),
         photoSaver: @escaping ([UIImage]) async throws -> Void = PhotoLibrarySaver.save(images:)) {
        self.store = store
        self.photoSaver = photoSaver
        resumeState = nil
        print("[Nine] RollViewModel initialized")
    }

    func loadRolls(autoResume: Bool = false) async {
        print("[Nine] RollStore load started")
        await flushPendingPersistence()
        let version = stateVersion
        do {
            let result = try await store.loadRolls()
            guard version == stateVersion else { return }
            storedRolls = result.rolls
                .filter { $0.phase == .complete }
                .map(archiveReady)
            savedFirstPassRolls = result.rolls
                .filter(\.isSavedFirstPassRoll)
                .filter(\.canResumeWork)
                .sorted { $0.updatedAt > $1.updatedAt }
            resumableRoll = result.rolls
                .filter { $0.canResumeWork && !$0.isSavedFirstPassRoll }
                .sorted { $0.updatedAt > $1.updatedAt }
                .first
            for roll in pendingSnapshots.values where !deletedRollIDs.contains(roll.id) {
                if roll.isSavedFirstPassRoll {
                    upsertSavedFirstPassRoll(roll)
                    if resumableRoll?.id == roll.id { resumableRoll = nil }
                } else if roll.canResumeWork {
                    resumableRoll = roll
                }
            }
            resumeState = resumableRoll.map(RollResumeState.init)
            unavailableRollCount = result.unavailableRollCount
            print("[Nine] RollStore load completed · active roll found: \(resumableRoll != nil) · saved first-pass rolls: \(savedFirstPassRolls.count) · completed rolls: \(storedRolls.count) · unavailable: \(unavailableRollCount)")
            if result.unavailableRollCount > 0 {
                statusMessage = "\(result.unavailableRollCount) saved roll could not be restored."
            } else if result.repairedRollCount > 0 {
                statusMessage = "A saved roll was recovered to its last complete exposure."
            }
            if autoResume {
                _ = await resolveLaunchResumeRoll()
            }
        } catch {
            guard version == stateVersion else { return }
            print("[Nine] RollStore load failed · \(error.localizedDescription)")
            statusMessage = error.localizedDescription
        }
    }

    func startRoll(mode: RollMode) async {
        print("[Nine] start roll requested · mode: \(mode.rawValue)")
        guard !isStartingRoll, !hasInProgressRoll else { return }
        isStartingRoll = true
        defer { isStartingRoll = false }
        stateVersion += 1
        let createdAt = Date()
        let title = RollTitleGenerator.nextDefaultTitle()
        let roll = Roll(createdAt: createdAt, mode: mode, title: title)
        activeRoll = roll
        resumableRoll = nil
        resumeState = RollResumeState(roll: roll)
        statusMessage = nil
        do {
            try await persist(roll)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    var hasInProgressRoll: Bool {
        (activeRoll?.canResumeWork == true && activeRoll?.isSavedFirstPassRoll != true)
            || resumableRoll?.canResumeWork == true
            || resumeState != nil
    }

    var canSaveFirstPassForLater: Bool {
        savedFirstPassRolls.count < Self.savedFirstPassLimit
    }

    func parkActiveRollForLibrary() {
        stateVersion += 1
        guard var roll = activeRoll, roll.canResumeWork else { return }
        roll.touch()
        if roll.isSavedFirstPassRoll {
            upsertSavedFirstPassRoll(roll)
        } else {
            resumableRoll = roll
            resumeState = RollResumeState(roll: roll)
        }
        activeRoll = nil
        enqueuePersistence(for: roll)
    }

    func continueRoll() {
        print("[Nine] continue roll requested · hydrated: \(resumableRoll != nil) · cached resume: \(resumeState != nil)")
        if let roll = activeRoll, roll.canResumeWork {
            beginDevelopmentIfNeeded(roll)
            return
        }
        guard let roll = resumableRoll else {
            if let resumeState {
                Task { await hydrateAndContinueRoll(id: resumeState.id) }
            }
            return
        }
        guard roll.canResumeWork else {
            resumableRoll = nil
            resumeState = nil
            return
        }
        stateVersion += 1
        let continuedRoll = squareNormalized(roll)
        activeRoll = continuedRoll
        beginDevelopmentIfNeeded(continuedRoll)
        statusMessage = nil
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard self.activeRoll?.id == continuedRoll.id else { return }
            if self.resumableRoll?.id == continuedRoll.id { self.resumableRoll = nil }
            if self.resumeState?.id == continuedRoll.id { self.resumeState = nil }
        }
    }

    func beginSecondPassForActiveRoll() async {
        guard !isSavingFirstPass, var roll = activeRoll else { return }
        do {
            try roll.beginSecondPass()
            activeRoll = roll
            if roll.isSavedFirstPassRoll {
                upsertSavedFirstPassRoll(roll)
            } else {
                resumeState = RollResumeState(roll: roll)
            }
            statusMessage = nil
            try await persist(roll)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    @discardableResult
    func saveFirstPassForLater() async -> Bool {
        guard !isSavingFirstPass, var roll = activeRoll,
              roll.phase == .awaitingSecondPass,
              roll.firstPassImages.count == Roll.frameCount else {
            return false
        }

        guard canSaveFirstPassForLater || savedFirstPassRolls.contains(where: { $0.id == roll.id }) else {
            statusMessage = "You already have 3 saved rolls. Finish or delete one before saving another."
            return false
        }

        isSavingFirstPass = true
        defer { isSavingFirstPass = false }
        roll.isSavedFirstPassRoll = true
        roll.touch()
        // Publish the same intention that is queued for disk. A scene save
        // during this await must not turn the saved roll back into a normal roll.
        activeRoll = roll
        upsertSavedFirstPassRoll(roll)
        if resumableRoll?.id == roll.id { resumableRoll = nil }
        if resumeState?.id == roll.id { resumeState = nil }
        do {
            try await persist(roll)
            if activeRoll?.id == roll.id { activeRoll = nil }
            if resumableRoll?.id == roll.id { resumableRoll = nil }
            if resumeState?.id == roll.id { resumeState = nil }
            statusMessage = nil
            return true
        } catch {
            statusMessage = error.localizedDescription
            return false
        }
    }

    func resumeSavedFirstPass(_ roll: Roll) async {
        stateVersion += 1
        let version = stateVersion
        do {
            await flushPendingPersistence()
            let hydratedRoll = try await store.loadRoll(id: roll.id)
            guard version == stateVersion, !deletedRollIDs.contains(roll.id) else { return }
            let restored = pendingSnapshots[roll.id] ?? hydratedRoll
            guard var secondPassRoll = restored,
                  secondPassRoll.isSavedFirstPassRoll, secondPassRoll.canResumeWork else {
                statusMessage = "The saved roll could not be restored."
                return
            }
            if let current = activeRoll, !current.isSavedFirstPassRoll, current.canResumeWork {
                resumableRoll = current
                resumeState = RollResumeState(roll: current)
            }
            if secondPassRoll.phase == .awaitingSecondPass {
                try secondPassRoll.beginSecondPass()
            }
            activeRoll = squareNormalized(secondPassRoll)
            upsertSavedFirstPassRoll(secondPassRoll)
            try await persist(secondPassRoll)
            beginDevelopmentIfNeeded(secondPassRoll)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    @discardableResult
    func resolveLaunchResumeRoll() async -> Roll? {
        let version = stateVersion
        let token = await store.resumeToken()
        guard version == stateVersion else { return nil }
        var candidate = resumableRoll
        if let token {
            do {
                let diskRoll = try await store.loadRoll(id: token.rollID)
                let loaded = pendingSnapshots[token.rollID] ?? diskRoll
                guard version == stateVersion else { return nil }
                if isValidResumeRoll(loaded, resume: token) {
                    candidate = loaded
                } else {
                    await store.clearResumeToken()
                }
            } catch {
                await store.clearResumeToken()
                statusMessage = error.localizedDescription
            }
        }
        guard version == stateVersion,
              let roll = candidate, roll.canResumeWork, !roll.isSavedFirstPassRoll else { return nil }
        let resumedRoll = squareNormalized(roll)
        activeRoll = resumedRoll
        resumableRoll = nil
        resumeState = RollResumeState(roll: resumedRoll)
        beginDevelopmentIfNeeded(resumedRoll)
        return resumedRoll
    }

    func discardResumableAndStart(mode: RollMode) async {
        guard !isReplacingRoll else { return }
        isReplacingRoll = true
        defer { isReplacingRoll = false }
        let normal = activeRoll.flatMap { !$0.isSavedFirstPassRoll && $0.canResumeWork ? $0 : nil }
            ?? resumableRoll
        if let id = normal?.id ?? resumeState?.id {
            removeRollFromMemory(id: id)
            guard await enqueueDeletion(id: id).value else {
                await loadRolls()
                return
            }
        }
        await startRoll(mode: mode)
    }

    func open(_ roll: Roll) {
        print("[Nine] open completed roll · \(roll.id.uuidString)")
        stateVersion += 1
        activeRoll = archiveReady(roll)
        statusMessage = nil
    }

    func renameRoll(id: UUID, to title: String) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty, !deletedRollIDs.contains(id), var roll = rollInMemory(id: id) else { return }
        roll.rename(to: trimmedTitle)
        updateRollInMemory(roll)
        enqueuePersistence(for: roll)
    }

    func deleteStoredRolls(at offsets: IndexSet) {
        let rolls = offsets.compactMap { storedRolls[safe: $0] }
        rolls.forEach(deleteStoredRoll)
    }

    func deleteStoredRoll(_ roll: Roll) {
        removeRollFromMemory(id: roll.id)
        let task = enqueueDeletion(id: roll.id)
        Task {
            if !(await task.value) { await loadRolls() }
        }
    }

    func deleteSavedFirstPassRoll(_ roll: Roll) {
        deleteStoredRoll(roll)
    }

    func returnHome() {
        if activeRoll?.canResumeWork == true {
            parkActiveRollForLibrary()
        } else {
            stateVersion += 1
            activeRoll = nil
        }
    }

    func clearSavedOverlayMessage(_ message: String) {
        guard savedOverlayMessage == message else { return }
        savedOverlayMessage = nil
    }

    func recordCapture(_ image: UIImage, metadata: [String: String]? = nil,
                       rollID: UUID? = nil) async throws -> CaptureMilestone {
        guard let id = rollID ?? activeRoll?.id, let original = rollInMemory(id: id),
              original.requiresCaptureInput, !captureIDs.contains(id) else {
            throw RollError.captureUnavailable
        }
        captureIDs.insert(id)
        defer { captureIDs.remove(id) }
        guard let data = await encodedJPEGData(from: image) else { throw RollError.imageEncodingFailed }
        // Encoding can yield to navigation, renaming, or deletion. Append to the
        // latest copy of the same roll; never resurrect a deleted/replaced roll.
        guard !deletedRollIDs.contains(id), var roll = rollInMemory(id: id),
              roll.phase == original.phase, roll.capturedFrameCount == original.capturedFrameCount else {
            throw RollError.captureUnavailable
        }
        let frame = CapturedFrame(imageData: data, metadata: metadata)
        let milestone = try roll.append(frame)
        updateRollInMemory(roll)
        enqueuePersistence(for: roll)
        if milestone == .secondPassComplete { beginDevelopmentIfNeeded(roll) }
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
        // Enqueue immediately, in mutation order. Finishing a save must never
        // assign its snapshot back to the live roll after an await.
        if let roll = activeRoll, roll.phase != .complete {
            _ = await enqueuePersistence(for: roll).value
        } else {
            await flushPendingPersistence()
        }
    }

    func retryPersistence() async {
        guard !isRetryingPersistence else { return }
        isRetryingPersistence = true
        defer { isRetryingPersistence = false }
        await flushPendingPersistence()
        let snapshots = pendingSnapshots.values.filter { !deletedRollIDs.contains($0.id) }
        for roll in snapshots { _ = await enqueuePersistence(for: roll).value }
        if persistenceError == nil {
            if statusMessage == RollError.persistenceFailed.localizedDescription { statusMessage = nil }
            let recoveryIDs = Set(snapshots.map(\.id)).union(completedPendingSave.keys)
            for id in recoveryIDs {
                if let roll = rollInMemory(id: id) { beginDevelopmentIfNeeded(roll) }
            }
            if let roll = activeRoll { beginDevelopmentIfNeeded(roll) }
        }
    }

    func retryDevelopment() {
        guard let roll = activeRoll else { return }
        beginDevelopmentIfNeeded(roll)
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

    private func beginDevelopmentIfNeeded(_ roll: Roll) {
        guard roll.phase == .developing, roll.canResumeWork,
              !deletedRollIDs.contains(roll.id), !developingRollIDs.contains(roll.id) else { return }
        developingRollIDs.insert(roll.id)
        developmentErrors.removeValue(forKey: roll.id)
        Task { await develop(roll) }
    }

    private func develop(_ source: Roll) async {
        defer { developingRollIDs.remove(source.id) }
        do {
            await flushPendingPersistence()
            guard !deletedRollIDs.contains(source.id) else { return }
            guard !failedSaveIDs.contains(source.id) else { throw RollError.persistenceFailed }
            var roll: Roll
            if let completed = completedPendingSave[source.id] {
                roll = completed
            } else {
                roll = source
                let images = try await blendEngine.develop(roll)
                guard !deletedRollIDs.contains(source.id) else { return }
                let grid = GridRenderer.render(images: images)
                try roll.finishDevelopment(images: images, gridImage: grid)
                if let latest = rollInMemory(id: source.id) { roll.title = latest.title }
                completedPendingSave[roll.id] = roll
            }
            try await persist(roll)
            guard !deletedRollIDs.contains(roll.id) else { return }
            roll = completedPendingSave[roll.id] ?? roll
            let visibleRoll = archiveReady(roll)
            if activeRoll?.id == roll.id { activeRoll = visibleRoll }
            if resumableRoll?.id == roll.id { resumableRoll = nil }
            if resumeState?.id == roll.id { resumeState = nil }
            savedFirstPassRolls.removeAll { $0.id == roll.id }
            storedRolls.removeAll { $0.id == roll.id }
            storedRolls.insert(visibleRoll, at: 0)
            completedPendingSave.removeValue(forKey: roll.id)
            developmentErrors.removeValue(forKey: roll.id)
            var output = roll.blendedImages
            if let grid = roll.gridImage { output.append(grid) }
            await saveToPhotos(output, completionText: nil, overlayText: "✓ Saved to Photos")
        } catch {
            if !deletedRollIDs.contains(source.id) {
                developmentErrors[source.id] = "This roll could not finish developing. Your exposures have been kept."
            }
        }
    }

    private func saveToPhotos(_ images: [UIImage], completionText: String?, overlayText: String? = nil) async {
        isExporting = true
        defer { isExporting = false }
        do {
            try await photoSaver(images)
            statusMessage = completionText
            savedOverlayMessage = overlayText
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

    private var activeRollIsSavedLibraryRoll: Bool {
        activeRoll?.isSavedFirstPassRoll == true
            && activeRoll?.requiresCaptureInput == true
    }

    private func upsertSavedFirstPassRoll(_ roll: Roll) {
        guard roll.isSavedFirstPassRoll,
              roll.canResumeWork else { return }
        savedFirstPassRolls.removeAll { $0.id == roll.id }
        savedFirstPassRolls.insert(roll, at: 0)
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
        let version = stateVersion
        do {
            await flushPendingPersistence()
            let result = try await store.loadRolls()
            guard version == stateVersion, !deletedRollIDs.contains(id) else { return }
            guard let roll = pendingSnapshots[id] ?? result.rolls.first(where: {
                $0.id == id && $0.canResumeWork && !$0.isSavedFirstPassRoll
            }) else {
                resumeState = nil
                statusMessage = "The saved roll could not be restored."
                print("[Nine] hydrate active roll failed · roll not found")
                return
            }
            resumableRoll = roll
            print("[Nine] hydrate active roll completed · phase: \(roll.phase.rawValue) · frame count: \(roll.capturedFrameCount)")
            continueRoll()
        } catch {
            guard version == stateVersion else { return }
            print("[Nine] hydrate active roll failed · \(error.localizedDescription)")
            resumeState = nil
            statusMessage = error.localizedDescription
        }
    }

    private func rollInMemory(id: UUID) -> Roll? {
        if let roll = activeRoll, roll.id == id { return roll }
        if let roll = resumableRoll, roll.id == id { return roll }
        return savedFirstPassRolls.first { $0.id == id } ?? storedRolls.first { $0.id == id }
    }

    private func updateRollInMemory(_ roll: Roll) {
        if activeRoll?.id == roll.id { activeRoll = roll }
        if let index = storedRolls.firstIndex(where: { $0.id == roll.id }) { storedRolls[index] = roll }
        if roll.isSavedFirstPassRoll {
            upsertSavedFirstPassRoll(roll)
        } else if roll.canResumeWork {
            if resumableRoll?.id == roll.id { resumableRoll = roll }
            resumeState = RollResumeState(roll: roll)
        }
    }

    private func removeRollFromMemory(id: UUID) {
        stateVersion += 1
        deletedRollIDs.insert(id)
        if activeRoll?.id == id { activeRoll = nil }
        if resumableRoll?.id == id { resumableRoll = nil }
        if resumeState?.id == id { resumeState = nil }
        storedRolls.removeAll { $0.id == id }
        savedFirstPassRolls.removeAll { $0.id == id }
        pendingSnapshots.removeValue(forKey: id)
        pendingSequences.removeValue(forKey: id)
        completedPendingSave.removeValue(forKey: id)
        developmentErrors.removeValue(forKey: id)
        failedSaveIDs.remove(id)
        updatePersistenceError()
    }

    private func persist(_ roll: Roll) async throws {
        guard await enqueuePersistence(for: roll).value else { throw RollError.persistenceFailed }
    }

    @discardableResult
    private func enqueuePersistence(for snapshot: Roll) -> Task<Bool, Never> {
        // A scene save during the final disk write must not put a developing
        // snapshot back on disk after the completed result.
        var roll = completedPendingSave[snapshot.id] ?? snapshot
        if completedPendingSave[snapshot.id] != nil, snapshot.updatedAt > roll.updatedAt {
            roll.title = snapshot.title
            roll.updatedAt = snapshot.updatedAt
            completedPendingSave[roll.id] = roll
        }
        let previousTask = persistenceTask
        persistenceSequence += 1
        stateVersion += 1
        let sequence = persistenceSequence
        if !deletedRollIDs.contains(roll.id) {
            pendingSnapshots[roll.id] = roll
            pendingSequences[roll.id] = sequence
        }
        let task = Task { [self] in
            _ = await previousTask?.value
            guard !deletedRollIDs.contains(roll.id) else { return false }
            do {
                try await store.save(roll)
                if pendingSequences[roll.id] == sequence {
                    pendingSnapshots.removeValue(forKey: roll.id)
                    pendingSequences.removeValue(forKey: roll.id)
                }
                failedSaveIDs.remove(roll.id)
                updatePersistenceError()
                return true
            } catch {
                if !deletedRollIDs.contains(roll.id) { failedSaveIDs.insert(roll.id) }
                updatePersistenceError()
                return false
            }
        }
        persistenceTask = task
        return task
    }

    private func enqueueDeletion(id: UUID) -> Task<Bool, Never> {
        let previousTask = persistenceTask
        persistenceSequence += 1
        let task = Task { [self] in
            _ = await previousTask?.value
            do {
                try await store.discardRoll(id: id)
                return true
            } catch {
                deletedRollIDs.remove(id)
                statusMessage = "The roll could not be deleted. Please try again."
                return false
            }
        }
        persistenceTask = task
        return task
    }

    private func updatePersistenceError() {
        persistenceError = failedSaveIDs.isEmpty ? nil : RollError.persistenceFailed.localizedDescription
    }

    func flushPendingPersistence() async {
        // Include saves enqueued while an earlier save is suspended.
        while let task = persistenceTask {
            let sequence = persistenceSequence
            _ = await task.value
            if sequence == persistenceSequence {
                persistenceTask = nil
                return
            }
        }
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
