import XCTest
import UIKit

final class ImageProcessingTests: XCTestCase {
    func testSquareImageCropsToShortestSide() {
        let image = makeImage(size: CGSize(width: 30, height: 18))

        let square = GridRenderer.squareImage(image)

        XCTAssertEqual(square.size.width, 18)
        XCTAssertEqual(square.size.height, 18)
    }

    func testContactSheetRequiresNineImages() {
        let eightImages = (0..<8).map { makeImage(index: $0) }
        let nineImages = (0..<Roll.frameCount).map { makeImage(index: $0) }

        XCTAssertNil(GridRenderer.render(images: eightImages, side: 300))
        XCTAssertNotNil(GridRenderer.render(images: nineImages, side: 300))
    }

    func testContactSheetIsSquare() throws {
        let images = (0..<Roll.frameCount).map { makeImage(index: $0, size: CGSize(width: 30, height: 18)) }

        let contactSheet = try XCTUnwrap(GridRenderer.render(images: images, side: 300))

        XCTAssertEqual(contactSheet.size.width, 300)
        XCTAssertEqual(contactSheet.size.height, 300)
    }

    func testBlendEngineProducesNineSquareOutputs() async throws {
        var roll = try makeAwaitingSecondPassRoll()
        try roll.beginSecondPass()
        for index in 0..<Roll.frameCount {
            _ = try roll.append(makeFrame(index: index + 70, size: CGSize(width: 24, height: 18)))
        }

        let outputs = try await BlendEngine().develop(roll)

        XCTAssertEqual(outputs.count, Roll.frameCount)
        for output in outputs {
            XCTAssertEqual(output.size.width, output.size.height)
        }
    }
}
