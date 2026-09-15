import XCTest
import UIKit

final class RollStoreTests: XCTestCase {
    private var temporaryRoot: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("NineTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryRoot {
            try? FileManager.default.removeItem(at: temporaryRoot)
        }
        temporaryRoot = nil
        try super.tearDownWithError()
    }

    func testSaveAndRestorePartialFirstPassRoll() async throws {
        let store = makeStore()
        var roll = Roll(mode: .desaturated, title: "Roll 001")
        for index in 0..<3 {
            _ = try roll.append(makeFrame(index: index))
        }

        try await store.save(roll)
        let restored = try await store.loadRoll(id: roll.id)

        XCTAssertEqual(restored?.phase, .firstPass)
        XCTAssertEqual(restored?.firstPassImages.count, 3)
        XCTAssertEqual(restored?.secondPassImages.count, 0)
        XCTAssertEqual(restored?.mode, .desaturated)
        XCTAssertTrue(restored?.requiresCaptureInput == true)
    }

    func testSaveAndRestoreAwaitingSecondPassSavedRoll() async throws {
        let store = makeStore()
        var roll = try makeAwaitingSecondPassRoll()
        roll.isSavedFirstPassRoll = true

        try await store.save(roll)
        let result = try await store.loadRolls()
        let restored = try XCTUnwrap(result.rolls.first { $0.id == roll.id })

        XCTAssertEqual(restored.phase, .awaitingSecondPass)
        XCTAssertEqual(restored.firstPassImages.count, Roll.frameCount)
        XCTAssertTrue(restored.isSavedFirstPassRoll)
        XCTAssertFalse(restored.requiresCaptureInput)
    }

    func testSaveAndRestorePartialSecondPassSavedRoll() async throws {
        let store = makeStore()
        var roll = try makeAwaitingSecondPassRoll()
        roll.isSavedFirstPassRoll = true
        try roll.beginSecondPass()
        _ = try roll.append(makeFrame(index: 30))
        _ = try roll.append(makeFrame(index: 31))

        try await store.save(roll)
        let restored = try await store.loadRoll(id: roll.id)

        XCTAssertEqual(restored?.phase, .secondPass)
        XCTAssertEqual(restored?.firstPassImages.count, Roll.frameCount)
        XCTAssertEqual(restored?.secondPassImages.count, 2)
        XCTAssertTrue(restored?.isSavedFirstPassRoll == true)
        XCTAssertTrue(restored?.requiresCaptureInput == true)
        XCTAssertNil(ResumeRollState(roll: restored!))
    }

    func testCompletedRollDropsSourceFramesAndRestoresFromDevelopedOutput() async throws {
        let store = makeStore()
        let roll = try makeCompletedRoll()

        try await store.save(roll)

        let rollDirectory = temporaryRoot.appendingPathComponent(roll.id.uuidString, isDirectory: true)
        XCTAssertTrue(try contentsCount(of: rollDirectory.appendingPathComponent("first", isDirectory: true)) == 0)
        XCTAssertTrue(try contentsCount(of: rollDirectory.appendingPathComponent("second", isDirectory: true)) == 0)
        XCTAssertTrue(try contentsCount(of: rollDirectory.appendingPathComponent("blended", isDirectory: true)) == Roll.frameCount)
        XCTAssertTrue(FileManager.default.fileExists(atPath: rollDirectory.appendingPathComponent("grid.jpg").path))

        let restored = try await store.loadRoll(id: roll.id)

        XCTAssertEqual(restored?.phase, .complete)
        XCTAssertEqual(restored?.firstPassImages.count, 0)
        XCTAssertEqual(restored?.secondPassImages.count, 0)
        XCTAssertEqual(restored?.blendedImages.count, Roll.frameCount)
        XCTAssertNotNil(restored?.gridImage)
        XCTAssertFalse(restored?.isSavedFirstPassRoll == true)
    }

    func testMissingCompletedGridIsRepaired() async throws {
        let store = makeStore()
        let roll = try makeCompletedRoll()
        try await store.save(roll)

        let gridURL = temporaryRoot
            .appendingPathComponent(roll.id.uuidString, isDirectory: true)
            .appendingPathComponent("grid.jpg")
        try FileManager.default.removeItem(at: gridURL)

        let result = try await store.loadRolls()
        let restored = try XCTUnwrap(result.rolls.first { $0.id == roll.id })

        XCTAssertEqual(result.repairedRollCount, 1)
        XCTAssertEqual(restored.phase, .complete)
        XCTAssertNotNil(restored.gridImage)
    }

    private func makeStore() -> RollStore {
        RollStore(directoryURL: temporaryRoot, shouldUpdateResumeCache: false)
    }

    private func contentsCount(of directory: URL) throws -> Int {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).count
    }
}

private func makeCompletedRoll() throws -> Roll {
    var roll = try makeAwaitingSecondPassRoll()
    try roll.beginSecondPass()
    for index in 0..<Roll.frameCount {
        _ = try roll.append(makeFrame(index: index + 100))
    }
    let images = (0..<Roll.frameCount).map { makeImage(index: $0 + 200) }
    try roll.finishDevelopment(images: images, gridImage: GridRenderer.render(images: images))
    return roll
}

// Regression tests use temporary storage and injected Photos saving.
@MainActor
final class RecoveryRegressionTests: XCTestCase {
    private func makeAuditStore(fileManager: FileManager = .default) -> RollStore {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("NineAudit-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return RollStore(fileManager: fileManager, directoryURL: root, shouldUpdateResumeCache: false)
    }

    func testUnshelvedFirstPassRemainsReachableAfterRelaunch() async throws {
        let store = makeAuditStore()
        let roll = try makeAwaitingSecondPassRoll()
        try await store.save(roll)
        let restored = try await store.loadRoll(id: roll.id)
        XCTAssertEqual(restored?.firstPassImages.count, 9)
        let model = RollViewModel(store: store)
        await model.loadRolls()
        XCTAssertTrue(model.hasInProgressRoll || model.savedFirstPassRolls.contains { $0.id == roll.id },
                      "Nine intact first-pass frames must remain reachable after relaunch")
    }

    func testInterruptedDevelopmentRemainsReachableAfterRelaunch() async throws {
        let store = makeAuditStore()
        var roll = try makeAwaitingSecondPassRoll()
        try roll.beginSecondPass()
        for index in 0..<9 { _ = try roll.append(makeFrame(index: index + 50)) }
        try await store.save(roll)
        let restored = try await store.loadRoll(id: roll.id)
        XCTAssertEqual(restored?.phase, .developing)
        XCTAssertEqual(restored?.secondPassImages.count, 9)
        let model = RollViewModel(store: store)
        await model.loadRolls()
        let visibleIDs = [model.activeRoll?.id, model.resumableRoll?.id].compactMap { $0 }
            + model.savedFirstPassRolls.map(\.id) + model.storedRolls.map(\.id)
        XCTAssertTrue(visibleIDs.contains(roll.id), "An interrupted 18-frame roll needs a recovery path")
    }

    func testOpeningSavedRollPreservesSeparateUnfinishedRoll() async throws {
        let store = makeAuditStore()
        var partial = Roll(mode: .desaturated)
        _ = try partial.append(makeFrame())
        var saved = try makeAwaitingSecondPassRoll()
        saved.isSavedFirstPassRoll = true
        try await store.save(partial)
        try await store.save(saved)
        let model = RollViewModel(store: store)
        await model.loadRolls()
        XCTAssertEqual(model.resumableRoll?.id, partial.id)
        await model.resumeSavedFirstPass(saved)
        model.parkActiveRollForLibrary()
        XCTAssertEqual(model.resumableRoll?.id, partial.id,
                       "Returning from a Saved Roll must retain the other roll's Continue action")
        await model.flushPendingPersistence()
    }

    func testBackgroundSaveCannotRewindACapture() async throws {
        let fileManager = AuditBlockingFileManager()
        let store = makeAuditStore(fileManager: fileManager)
        let model = RollViewModel(store: store)
        await model.startRoll(mode: .freeform)
        _ = try await model.recordCapture(makeImage(index: 1))
        await model.persistActiveRoll()
        let enteredSave = expectation(description: "Background save holds the one-frame snapshot")
        fileManager.pauseNextSave { enteredSave.fulfill() }
        let backgroundSave = Task { await model.persistActiveRoll() }
        await fulfillment(of: [enteredSave], timeout: 5)
        _ = try await model.recordCapture(makeImage(index: 2))
        XCTAssertEqual(model.activeRoll?.firstPassImages.count, 2)
        fileManager.releaseSave()
        await backgroundSave.value
        XCTAssertEqual(model.activeRoll?.firstPassImages.count, 2,
                       "An older background save must not overwrite the newly captured frame")
        // Drain tasks before removing this test's temporary data.
        await model.persistActiveRoll()
    }

    func testIncompleteCompletedArchiveIsReportedUnavailable() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("NineAudit-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = RollStore(directoryURL: root, shouldUpdateResumeCache: false)
        let roll = try makeCompletedRoll()
        try await store.save(roll)
        let rollDirectory = root.appendingPathComponent(roll.id.uuidString)
        try FileManager.default.removeItem(at: rollDirectory.appendingPathComponent("blended/002.jpg"))
        let manifestURL = rollDirectory.appendingPathComponent("roll.json")
        let survivorURL = rollDirectory.appendingPathComponent("blended/003.jpg")
        let manifestBefore = try Data(contentsOf: manifestURL)
        let survivorBefore = try Data(contentsOf: survivorURL)
        let result = try await store.loadRolls()
        XCTAssertEqual(try Data(contentsOf: manifestURL), manifestBefore)
        XCTAssertEqual(try Data(contentsOf: survivorURL), survivorBefore)
        XCTAssertEqual(result.unavailableRollCount, 1,
                       "A damaged completed archive must not be reclassified as a fresh camera roll")
        XCTAssertFalse(result.rolls.contains { $0.id == roll.id && $0.phase == .firstPass })
    }
}

private final class AuditBlockingFileManager: FileManager, @unchecked Sendable {
    private let auditLock = NSLock()
    private let auditGate = DispatchSemaphore(value: 0)
    private var auditOnCreate: (() -> Void)?
    private var pauseFolder: String?
    private var failsSaves = false

    func setSaveFailure(_ enabled: Bool) {
        auditLock.lock()
        failsSaves = enabled
        auditLock.unlock()
    }

    func pauseNextSave(folder: String? = nil, _ callback: @escaping () -> Void) {
        auditLock.lock()
        auditOnCreate = callback
        pauseFolder = folder
        auditLock.unlock()
    }

    func releaseSave() { auditGate.signal() }

    override func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool,
                                  attributes: [FileAttributeKey: Any]? = nil) throws {
        auditLock.lock()
        let callback = pauseFolder == nil || pauseFolder == url.lastPathComponent ? auditOnCreate : nil
        if callback != nil { auditOnCreate = nil }
        let shouldFail = failsSaves && url.lastPathComponent == "blended"
        auditLock.unlock()
        if shouldFail { throw CocoaError(.fileWriteOutOfSpace) }
        if let callback {
            callback()
            guard auditGate.wait(timeout: .now() + 10) == .success else {
                throw NSError(domain: "NineAuditTimeout", code: 1)
            }
        }
        try super.createDirectory(at: url, withIntermediateDirectories: createIntermediates, attributes: attributes)
    }
}

extension RecoveryRegressionTests {
    func testRecoveredFirstPassReturnsToDecisionBeforeAcceptingMoreCaptures() async throws {
        let store = makeAuditStore()
        let roll = try makeAwaitingSecondPassRoll()
        try await store.save(roll)
        let model = RollViewModel(store: store)
        await model.loadRolls()
        let restored = await model.resolveLaunchResumeRoll()
        XCTAssertEqual(restored?.id, roll.id)
        XCTAssertEqual(restored?.phase, .awaitingSecondPass)
        XCTAssertTrue(restored?.canPresentCamera == true)
        XCTAssertFalse(restored?.requiresCaptureInput == true)
        await model.beginSecondPassForActiveRoll()
        _ = try await model.recordCapture(makeImage(index: 50))
        await model.flushPendingPersistence()
        let disk = try await store.loadRoll(id: roll.id)
        XCTAssertEqual(disk?.firstPassImages.map(\.imageData), roll.firstPassImages.map(\.imageData))
        XCTAssertEqual(disk?.secondPassImages.count, 1)
    }

    func testFullShootingSequenceStillDevelopsNineFramesAndOneGrid() async throws {
        let store = makeAuditStore()
        let exported = expectation(description: "Completed output sent to Photos")
        var exportedCount = 0
        let model = RollViewModel(store: store, photoSaver: { images in
            exportedCount = images.count
            exported.fulfill()
        })
        await model.startRoll(mode: .freeform)
        let id = try XCTUnwrap(model.activeRoll?.id)
        for index in 0..<9 {
            let milestone = try await model.recordCapture(makeImage(index: index))
            XCTAssertEqual(milestone, index == 8 ? .firstPassComplete : .frameCaptured)
        }
        XCTAssertEqual(model.activeRoll?.phase, .awaitingSecondPass)
        await model.beginSecondPassForActiveRoll()
        for index in 0..<9 {
            let milestone = try await model.recordCapture(makeImage(index: index + 20))
            XCTAssertEqual(milestone, index == 8 ? .secondPassComplete : .frameCaptured)
        }
        await fulfillment(of: [exported], timeout: 10)
        XCTAssertEqual(exportedCount, 10)
        XCTAssertEqual(model.activeRoll?.phase, .complete)
        XCTAssertEqual(model.storedRolls.map(\.id), [id])
        XCTAssertNil(model.resumableRoll)
        XCTAssertFalse(model.hasInProgressRoll)
        let disk = try await store.loadRoll(id: id)
        XCTAssertEqual(disk?.blendedImages.count, 9)
        XCTAssertNotNil(disk?.gridImage)
        XCTAssertEqual(disk?.firstPassImages.count, 0)
        XCTAssertEqual(disk?.secondPassImages.count, 0)
    }

    func testFailedSaveKeepsInFlightCaptureAndCanRetryAfterReturningHome() async throws {
        let manager = AuditBlockingFileManager()
        let store = makeAuditStore(fileManager: manager)
        let model = RollViewModel(store: store)
        await model.startRoll(mode: .freeform)
        let id = try XCTUnwrap(model.activeRoll?.id)
        manager.setSaveFailure(true)
        _ = try await model.recordCapture(makeImage(index: 1))
        await model.flushPendingPersistence()
        XCTAssertNotNil(model.persistenceError)
        // The preceding write may fail while the next shutter is already in flight.
        _ = try await model.recordCapture(makeImage(index: 2), rollID: id)
        model.parkActiveRollForLibrary()
        await model.loadRolls()
        XCTAssertEqual(model.resumableRoll?.firstPassImages.count, 2)
        XCTAssertNotNil(model.persistenceError)
        manager.setSaveFailure(false)
        await model.retryPersistence()
        XCTAssertNil(model.persistenceError)
        let fresh = RollViewModel(store: store)
        await fresh.loadRolls()
        let restored = await fresh.resolveLaunchResumeRoll()
        XCTAssertEqual(restored?.id, id)
        XCTAssertEqual(restored?.firstPassImages.count, 2)
    }

    func testFailedSaveForLaterCanRetryWithoutLosingItsNineExposures() async throws {
        let manager = AuditBlockingFileManager()
        let store = makeAuditStore(fileManager: manager)
        let roll = try makeAwaitingSecondPassRoll()
        try await store.save(roll)
        let model = RollViewModel(store: store)
        await model.loadRolls(autoResume: true)
        manager.setSaveFailure(true)
        let saved = await model.saveFirstPassForLater()
        XCTAssertFalse(saved)
        XCTAssertEqual(model.activeRoll?.firstPassImages.count, 9)
        manager.setSaveFailure(false)
        await model.retryPersistence()
        model.parkActiveRollForLibrary()
        await model.flushPendingPersistence()
        let fresh = RollViewModel(store: store)
        await fresh.loadRolls()
        XCTAssertEqual(fresh.savedFirstPassRolls.map(\.id), [roll.id])
        XCTAssertEqual(fresh.savedFirstPassRolls.first?.firstPassImages.count, 9)
        XCTAssertNil(fresh.resumableRoll)
    }

    func testBackgroundSaveCannotUndoSaveForLater() async throws {
        let manager = AuditBlockingFileManager()
        let store = makeAuditStore(fileManager: manager)
        let roll = try makeAwaitingSecondPassRoll()
        try await store.save(roll)
        let model = RollViewModel(store: store)
        await model.loadRolls(autoResume: true)
        let entered = expectation(description: "Save for later is pending")
        manager.pauseNextSave { entered.fulfill() }
        let shelve = Task { await model.saveFirstPassForLater() }
        await fulfillment(of: [entered], timeout: 5)
        let background = Task { await model.persistActiveRoll() }
        await Task.yield()
        manager.releaseSave()
        let saved = await shelve.value
        await background.value
        await model.flushPendingPersistence()
        XCTAssertTrue(saved)
        let disk = try await store.loadRoll(id: roll.id)
        XCTAssertTrue(disk?.isSavedFirstPassRoll == true)
        XCTAssertEqual(disk?.phase, .awaitingSecondPass)
    }

    func testDeleteWaitsForPendingSaveAndCannotResurrectRoll() async throws {
        let manager = AuditBlockingFileManager()
        let store = makeAuditStore(fileManager: manager)
        let model = RollViewModel(store: store)
        await model.startRoll(mode: .freeform)
        _ = try await model.recordCapture(makeImage(index: 1))
        await model.flushPendingPersistence()
        let roll = try XCTUnwrap(model.activeRoll)
        let entered = expectation(description: "A save is pending before delete")
        manager.pauseNextSave { entered.fulfill() }
        let saving = Task { await model.persistActiveRoll() }
        await fulfillment(of: [entered], timeout: 5)
        model.deleteStoredRoll(roll)
        manager.releaseSave()
        await saving.value
        await model.flushPendingPersistence()
        do {
            _ = try await model.recordCapture(makeImage(index: 2), rollID: roll.id)
            XCTFail("A late capture must not recreate a deleted roll")
        } catch { XCTAssertEqual(error as? RollError, .captureUnavailable) }
        let disk = try await store.loadRoll(id: roll.id)
        XCTAssertNil(disk)
        XCTAssertNil(model.activeRoll)
        XCTAssertFalse(model.hasInProgressRoll)
    }

    func testLateCaptureStaysWithParkedRollInsteadOfNewlyOpenedSavedRoll() async throws {
        let store = makeAuditStore()
        var saved = try makeAwaitingSecondPassRoll()
        saved.isSavedFirstPassRoll = true
        try await store.save(saved)
        let model = RollViewModel(store: store)
        await model.loadRolls()
        await model.startRoll(mode: .desaturated)
        let originalID = try XCTUnwrap(model.activeRoll?.id)
        model.parkActiveRollForLibrary()
        await model.resumeSavedFirstPass(saved)
        _ = try await model.recordCapture(makeImage(index: 3), rollID: originalID)
        await model.flushPendingPersistence()
        XCTAssertEqual(model.activeRoll?.id, saved.id)
        XCTAssertEqual(model.activeRoll?.secondPassImages.count, 0)
        XCTAssertEqual(model.resumableRoll?.id, originalID)
        XCTAssertEqual(model.resumableRoll?.firstPassImages.count, 1)
    }

    func testRecoveredDevelopmentRetriesFailedFinalSaveWithSourcesIntact() async throws {
        let manager = AuditBlockingFileManager()
        let store = makeAuditStore(fileManager: manager)
        let roll = try developingRoll()
        try await store.save(roll)
        let exported = expectation(description: "Retry completes and exports")
        var exportCount = 0
        let model = RollViewModel(store: store, photoSaver: { images in
            exportCount += 1
            XCTAssertEqual(images.count, 10)
            exported.fulfill()
        })
        await model.loadRolls()
        manager.setSaveFailure(true)
        _ = await model.resolveLaunchResumeRoll()
        await waitUntil { model.developmentError != nil }
        XCTAssertEqual(model.activeRoll?.firstPassImages.count, 9)
        XCTAssertEqual(model.activeRoll?.secondPassImages.count, 9)
        XCTAssertEqual(model.storedRolls.count, 0)
        manager.setSaveFailure(false)
        let beforeRetry = try await store.loadRoll(id: roll.id)
        XCTAssertEqual(beforeRetry?.phase, .developing)
        XCTAssertEqual(beforeRetry?.secondPassImages.count, 9)
        await model.retryPersistence()
        await fulfillment(of: [exported], timeout: 10)
        XCTAssertEqual(exportCount, 1)
        XCTAssertNil(model.persistenceError)
        XCTAssertNil(model.developmentError)
        let disk = try await store.loadRoll(id: roll.id)
        XCTAssertEqual(disk?.phase, .complete)
        XCTAssertEqual(disk?.blendedImages.count, 9)
    }

    func testSceneSaveDuringFinalWriteCannotRewindCompletedRoll() async throws {
        let manager = AuditBlockingFileManager()
        let store = makeAuditStore(fileManager: manager)
        let roll = try developingRoll()
        try await store.save(roll)
        let exported = expectation(description: "Recovered development exports")
        let model = RollViewModel(store: store, photoSaver: { _ in exported.fulfill() })
        await model.loadRolls()
        let entered = expectation(description: "Final archive write is pending")
        manager.pauseNextSave(folder: "blended") { entered.fulfill() }
        _ = await model.resolveLaunchResumeRoll()
        await fulfillment(of: [entered], timeout: 10)
        model.renameRoll(id: roll.id, to: "Recovered Roll")
        let background = Task { await model.persistActiveRoll() }
        await Task.yield()
        manager.releaseSave()
        await background.value
        await fulfillment(of: [exported], timeout: 10)
        await model.flushPendingPersistence()
        let disk = try await store.loadRoll(id: roll.id)
        XCTAssertEqual(disk?.phase, .complete)
        XCTAssertEqual(disk?.title, "Recovered Roll")
        XCTAssertEqual(disk?.blendedImages.count, 9)
        XCTAssertEqual(disk?.firstPassImages.count, 0)
        XCTAssertEqual(model.activeRoll?.title, "Recovered Roll")
    }

    func testCompletingSavedRollPreservesIndependentNormalResume() async throws {
        let store = makeAuditStore()
        var normal = Roll(mode: .desaturated)
        _ = try normal.append(makeFrame())
        var saved = try developingRoll()
        saved.isSavedFirstPassRoll = true
        try await store.save(normal)
        try await store.save(saved)
        let exported = expectation(description: "Saved roll develops")
        let model = RollViewModel(store: store, photoSaver: { _ in exported.fulfill() })
        await model.loadRolls()
        await model.resumeSavedFirstPass(saved)
        await fulfillment(of: [exported], timeout: 10)
        XCTAssertEqual(model.resumableRoll?.id, normal.id)
        XCTAssertEqual(model.resumeState?.id, normal.id)
        XCTAssertTrue(model.savedFirstPassRolls.isEmpty)
        model.returnHome()
        model.continueRoll()
        XCTAssertEqual(model.activeRoll?.id, normal.id)
    }

    func testSavedRollLimitStillAllowsOnlyThree() async throws {
        let store = makeAuditStore()
        for _ in 0..<RollViewModel.savedFirstPassLimit {
            var saved = try makeAwaitingSecondPassRoll()
            saved.isSavedFirstPassRoll = true
            try await store.save(saved)
        }
        let normal = try makeAwaitingSecondPassRoll()
        try await store.save(normal)
        let model = RollViewModel(store: store)
        await model.loadRolls(autoResume: true)
        let saved = await model.saveFirstPassForLater()
        XCTAssertFalse(saved)
        XCTAssertEqual(model.savedFirstPassRolls.count, 3)
        XCTAssertEqual(model.activeRoll?.id, normal.id)
        XCTAssertFalse(model.activeRoll?.isSavedFirstPassRoll == true)
    }

    func testSavedAndCompletedRollWritesDoNotClearOtherResumeToken() async throws {
        let suite = "NineRecoveryDefaults-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = RollStore(directoryURL: root, resumeDefaults: defaults)
        let normal = try makeAwaitingSecondPassRoll()
        try await store.save(normal)
        var saved = try makeAwaitingSecondPassRoll()
        saved.isSavedFirstPassRoll = true
        try await store.save(saved)
        let tokenAfterSaved = await store.resumeToken()
        XCTAssertEqual(tokenAfterSaved?.rollID, normal.id)
        XCTAssertEqual(tokenAfterSaved?.phase, .awaitingSecondPass)
        try await store.discard(saved)
        let complete = try makeCompletedRoll()
        try await store.save(complete)
        let tokenAfterComplete = await store.resumeToken()
        XCTAssertEqual(tokenAfterComplete?.rollID, normal.id)
        try await store.discard(normal)
        let emptyToken = await store.resumeToken()
        XCTAssertNil(emptyToken)
    }

    private func developingRoll() throws -> Roll {
        var roll = try makeAwaitingSecondPassRoll()
        try roll.beginSecondPass()
        for index in 0..<9 { _ = try roll.append(makeFrame(index: index + 30)) }
        return roll
    }

    private func waitUntil(file: StaticString = #filePath, line: UInt = #line,
                           _ condition: () -> Bool) async {
        for _ in 0..<500 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for recovery state", file: file, line: line)
    }
}

extension RollStoreTests {
    func testDuplicateManifestPathsReportDamageWithoutMovingPhotographs() async throws {
        let store = makeStore()
        var roll = Roll(mode: .freeform)
        _ = try roll.append(makeFrame())
        try await store.save(roll)
        let directory = temporaryRoot.appendingPathComponent(roll.id.uuidString)
        let manifestURL = directory.appendingPathComponent("roll.json")
        var manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any])
        let frames = try XCTUnwrap(manifest["firstPassFrames"] as? [[String: Any]])
        manifest["firstPassFrames"] = frames + frames
        let damagedManifest = try JSONSerialization.data(withJSONObject: manifest)
        try damagedManifest.write(to: manifestURL)
        let imageURL = directory.appendingPathComponent("first/001.jpg")
        let imageBefore = try Data(contentsOf: imageURL)
        let result = try await store.loadRolls()
        XCTAssertEqual(result.unavailableRollCount, 1)
        XCTAssertTrue(result.rolls.isEmpty)
        XCTAssertEqual(try Data(contentsOf: imageURL), imageBefore)
        XCTAssertEqual(try Data(contentsOf: manifestURL), damagedManifest)
    }

    func testInvalidCaptureRecoversValidPrefixAndRetainsLaterFiles() async throws {
        let store = makeStore()
        var roll = Roll(mode: .freeform)
        for index in 0..<3 { _ = try roll.append(makeFrame(index: index)) }
        try await store.save(roll)
        let directory = temporaryRoot.appendingPathComponent(roll.id.uuidString)
        let laterImage = try Data(contentsOf: directory.appendingPathComponent("first/003.jpg"))
        try Data("invalid JPEG".utf8).write(to: directory.appendingPathComponent("first/002.jpg"))
        let result = try await store.loadRolls()
        XCTAssertEqual(result.repairedRollCount, 1)
        XCTAssertEqual(result.rolls.first?.firstPassImages.count, 1)
        let retained = try FileManager.default.contentsOfDirectory(at: directory.appendingPathComponent("orphaned"), includingPropertiesForKeys: nil)
        XCTAssertEqual(retained.count, 2)
        XCTAssertTrue(try retained.map { try Data(contentsOf: $0) }.contains(laterImage))
    }

    func testIncompleteCompletionCannotRemoveDurableSourceExposures() async throws {
        let store = makeStore()
        var roll = try makeAwaitingSecondPassRoll()
        try roll.beginSecondPass()
        for index in 0..<9 { _ = try roll.append(makeFrame(index: index + 20)) }
        try await store.save(roll)
        roll.phase = .complete
        roll.blendedImages = (0..<8).map { makeImage(index: $0) }
        do {
            try await store.save(roll)
            XCTFail("Incomplete output must not be committed as completed")
        } catch { XCTAssertEqual(error as? RollError, .storedRollDamaged) }
        let restored = try await store.loadRoll(id: roll.id)
        XCTAssertEqual(restored?.phase, .developing)
        XCTAssertEqual(restored?.firstPassImages.count, 9)
        XCTAssertEqual(restored?.secondPassImages.count, 9)
    }
}
