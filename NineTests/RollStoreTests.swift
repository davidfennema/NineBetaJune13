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
