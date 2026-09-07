import XCTest
import UIKit

final class RollModelTests: XCTestCase {
    func testFirstPassProgressionPausesAfterNineFrames() throws {
        var roll = Roll(mode: .freeform, title: "Roll 001")

        for index in 0..<(Roll.frameCount - 1) {
            let milestone = try roll.append(makeFrame(index: index))
            XCTAssertEqual(milestone, .frameCaptured)
            XCTAssertEqual(roll.phase, .firstPass)
            XCTAssertEqual(roll.firstPassImages.count, index + 1)
        }

        let milestone = try roll.append(makeFrame(index: Roll.frameCount - 1))

        XCTAssertEqual(milestone, .firstPassComplete)
        XCTAssertEqual(roll.phase, .awaitingSecondPass)
        XCTAssertEqual(roll.firstPassImages.count, Roll.frameCount)
        XCTAssertFalse(roll.requiresCaptureInput)
    }

    func testAwaitingSecondPassCannotAcceptCapture() throws {
        var roll = try makeAwaitingSecondPassRoll()

        XCTAssertThrowsError(try roll.append(makeFrame(index: 99))) { error in
            XCTAssertEqual(error as? RollError, .captureUnavailable)
        }
    }

    func testSecondPassProgressionMovesToDevelopingAfterNineFrames() throws {
        var roll = try makeAwaitingSecondPassRoll()
        try roll.beginSecondPass()

        for index in 0..<(Roll.frameCount - 1) {
            let milestone = try roll.append(makeFrame(index: index + 20))
            XCTAssertEqual(milestone, .frameCaptured)
            XCTAssertEqual(roll.phase, .secondPass)
            XCTAssertEqual(roll.secondPassImages.count, index + 1)
        }

        let milestone = try roll.append(makeFrame(index: 40))

        XCTAssertEqual(milestone, .secondPassComplete)
        XCTAssertEqual(roll.phase, .developing)
        XCTAssertFalse(roll.requiresCaptureInput)
    }

    func testResumeValidityExcludesSavedFirstPassRolls() throws {
        var roll = try makeAwaitingSecondPassRoll()
        roll.isSavedFirstPassRoll = true
        try roll.beginSecondPass()
        try roll.append(makeFrame(index: 50))

        let resume = ResumeRollState(
            rollID: roll.id,
            phase: roll.phase,
            firstPassCount: roll.firstPassImages.count,
            secondPassCount: roll.secondPassImages.count,
            updatedAt: roll.updatedAt
        )

        XCTAssertFalse(isValidResumeRoll(roll, resume: resume))
        XCTAssertNil(ResumeRollState(roll: roll))
    }

    func testHistoricalModeNamesDecodeToNatural() throws {
        let softFocus = try JSONDecoder().decode(RollMode.self, from: Data(#""softFocus""#.utf8))
        let motion = try JSONDecoder().decode(RollMode.self, from: Data(#""motion""#.utf8))

        XCTAssertEqual(softFocus, .freeform)
        XCTAssertEqual(motion, .freeform)
    }
}

func makeAwaitingSecondPassRoll() throws -> Roll {
    var roll = Roll(mode: .freeform, title: "Roll 001")
    for index in 0..<Roll.frameCount {
        _ = try roll.append(makeFrame(index: index))
    }
    return roll
}

func makeFrame(index: Int = 0, size: CGSize = CGSize(width: 16, height: 16)) -> CapturedFrame {
    CapturedFrame(imageData: makeImageData(index: index, size: size))
}

func makeImageData(index: Int = 0, size: CGSize = CGSize(width: 16, height: 16)) -> Data {
    makeImage(index: index, size: size).jpegData(compressionQuality: 0.9)!
}

func makeImage(index: Int = 0, size: CGSize = CGSize(width: 16, height: 16)) -> UIImage {
    let hue = CGFloat((index * 37) % 255) / 255
    let color = UIColor(hue: hue, saturation: 0.7, brightness: 0.8, alpha: 1)
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1
    format.opaque = true
    return UIGraphicsImageRenderer(size: size, format: format).image { context in
        color.setFill()
        context.fill(CGRect(origin: .zero, size: size))
    }
}
