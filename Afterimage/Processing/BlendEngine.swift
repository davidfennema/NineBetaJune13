import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

final class BlendEngine {
    private let context = CIContext(options: [.cacheIntermediates: true])

    func develop(_ roll: Roll) async throws -> [UIImage] {
        guard roll.firstPassImages.count == Roll.frameCount,
              roll.secondPassImages.count == Roll.frameCount else {
            throw RollError.developmentIncomplete
        }

        return try zip(roll.firstPassImages, roll.secondPassImages).enumerated().map { index, pair in
            let orientationOptions: [CIImageOption: Any] = [.applyOrientationProperty: true]
            guard let first = CIImage(data: pair.0.imageData, options: orientationOptions),
                  let second = CIImage(data: pair.1.imageData, options: orientationOptions) else {
                throw RollError.imageEncodingFailed
            }
            return try render(
                first: squareCrop(first),
                second: squareCrop(second),
                mode: roll.mode,
                frameIndex: index
            )
        }
    }

    private func render(first: CIImage, second: CIImage, mode: RollMode, frameIndex: Int) throws -> UIImage {
        let extent = first.extent
        let value = organicValue(frameIndex)
        let normalizedFirst = normalized(first, exposureOffset: -value.exposure / 2)
        let normalizedSecond = normalized(second, exposureOffset: value.exposure / 2)
        let translatedSecond = styled(
            normalizedSecond.clampedToExtent().transformed(
                by: CGAffineTransform(
                    translationX: value.offset.width * extent.width,
                    y: value.offset.height * extent.height
                )
            ),
            for: mode
        ).cropped(to: extent)

        let balancedFirst = exposureAdjusted(normalizedFirst, by: Float(-0.18 - value.balance))
        let balancedSecond = exposureAdjusted(translatedSecond, by: Float(-0.18 + value.balance))

        let blend = CIFilter.screenBlendMode()
        blend.inputImage = balancedSecond
        blend.backgroundImage = balancedFirst

        let contrast = CIFilter.colorControls()
        contrast.inputImage = blend.outputImage
        contrast.brightness = -0.035
        contrast.contrast = 0.98
        contrast.saturation = 0.98

        let tonalProtection = CIFilter.highlightShadowAdjust()
        tonalProtection.inputImage = contrast.outputImage
        tonalProtection.highlightAmount = 0.62
        tonalProtection.shadowAmount = 0.16

        guard let protectedImage = tonalProtection.outputImage?.cropped(to: extent),
              let result = finalStyle(protectedImage, for: mode),
              let cgImage = context.createCGImage(result, from: extent) else {
            throw RollError.imageEncodingFailed
        }
        return UIImage(cgImage: cgImage)
    }

    private func squareCrop(_ image: CIImage) -> CIImage {
        let side = min(image.extent.width, image.extent.height)
        let rect = CGRect(
            x: image.extent.midX - side / 2,
            y: image.extent.midY - side / 2,
            width: side,
            height: side
        )
        return image.cropped(to: rect).transformed(
            by: CGAffineTransform(translationX: -rect.minX, y: -rect.minY)
        )
    }

    private func normalized(_ image: CIImage, exposureOffset: CGFloat) -> CIImage {
        let luminance = averageLuminance(of: image)
        let adjustment = max(min(log2(0.42 / max(luminance, 0.04)), 0.7), -0.7) + exposureOffset
        let exposure = CIFilter.exposureAdjust()
        exposure.inputImage = image
        exposure.ev = Float(adjustment)
        return exposure.outputImage ?? image
    }

    private func averageLuminance(of image: CIImage) -> CGFloat {
        let average = CIFilter.areaAverage()
        average.inputImage = image
        average.extent = image.extent
        guard let output = average.outputImage else { return 0.42 }

        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(
            output,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        return (0.2126 * CGFloat(pixel[0]) + 0.7152 * CGFloat(pixel[1]) + 0.0722 * CGFloat(pixel[2])) / 255
    }

    private func exposureAdjusted(_ image: CIImage, by ev: Float) -> CIImage {
        let exposure = CIFilter.exposureAdjust()
        exposure.inputImage = image
        exposure.ev = ev
        return exposure.outputImage ?? image
    }

    private func styled(_ image: CIImage, for mode: RollMode) -> CIImage {
        switch mode {
        case .freeform:
            return image
        case .desaturated:
            let controls = CIFilter.colorControls()
            controls.inputImage = image
            controls.contrast = 1.04
            controls.saturation = 0.52
            controls.brightness = 0.01
            return controls.outputImage ?? image
        case .blackAndWhite:
            return image
        case .highContrast:
            let controls = CIFilter.colorControls()
            controls.inputImage = image
            controls.contrast = 1.22
            controls.saturation = 0.96
            return controls.outputImage ?? image
        }
    }

    private func finalStyle(_ image: CIImage, for mode: RollMode) -> CIImage? {
        switch mode {
        case .blackAndWhite:
            let monochrome = CIFilter.photoEffectNoir()
            monochrome.inputImage = image
            return monochrome.outputImage?.cropped(to: image.extent)
        case .desaturated:
            let controls = CIFilter.colorControls()
            controls.inputImage = image
            controls.contrast = 1.03
            controls.saturation = 0.42
            controls.brightness = 0.015
            return controls.outputImage?.cropped(to: image.extent)
        case .freeform, .highContrast:
            return image
        }
    }

    private func organicValue(_ index: Int) -> (balance: CGFloat, exposure: CGFloat, offset: CGSize) {
        let values: [(CGFloat, CGFloat, CGSize)] = [
            (0.010, 0.04, CGSize(width: 0.003, height: -0.004)),
            (-0.014, -0.03, CGSize(width: -0.005, height: 0.002)),
            (0.018, 0.02, CGSize(width: 0.004, height: 0.005)),
            (-0.010, -0.04, CGSize(width: -0.002, height: -0.004)),
            (0.014, 0.03, CGSize(width: 0.002, height: 0.001)),
            (-0.018, -0.01, CGSize(width: -0.005, height: -0.001)),
            (0.012, 0.04, CGSize(width: 0.003, height: 0.004)),
            (-0.012, -0.03, CGSize(width: -0.003, height: 0.003)),
            (0.008, 0.01, CGSize(width: 0.004, height: -0.003))
        ]
        return values[index % values.count]
    }
}
