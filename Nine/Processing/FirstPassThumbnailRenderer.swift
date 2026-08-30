import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import UIKit

enum FirstPassThumbnailRenderer {
    private static let cache = NSCache<NSString, UIImage>()
    private static let context = CIContext(options: [.cacheIntermediates: true])

    static func thumbnail(
        for frame: CapturedFrame,
        rollID: UUID,
        mode: RollMode,
        side: CGFloat
    ) -> UIImage? {
        let pixelSide = max(1, Int((side * UIScreen.main.scale).rounded(.up)))
        let key = "\(rollID.uuidString)-\(frame.id.uuidString)-\(mode.rawValue)-\(pixelSide)" as NSString

        if let cachedImage = cache.object(forKey: key) {
            return cachedImage
        }

        guard let sourceImage = downsampledImage(from: frame.imageData, maxPixelSize: pixelSide * 2) else {
            return nil
        }

        let squareImage = GridRenderer.squareImage(sourceImage)
        let renderedImage = styled(squareImage, mode: mode) ?? squareImage
        cache.setObject(renderedImage, forKey: key)
        return renderedImage
    }

    private static func downsampledImage(from data: Data, maxPixelSize: Int) -> UIImage? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else {
            return nil
        }

        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ] as CFDictionary

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    private static func styled(_ image: UIImage, mode: RollMode) -> UIImage? {
        guard mode.previewSaturation != 1 || mode.previewContrast != 1 else {
            return image
        }
        guard let input = CIImage(image: image) else {
            return nil
        }

        let controls = CIFilter.colorControls()
        controls.inputImage = input
        controls.saturation = Float(mode.previewSaturation)
        controls.contrast = Float(mode.previewContrast)

        guard let output = controls.outputImage?.cropped(to: input.extent),
              let cgImage = context.createCGImage(output, from: input.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage, scale: image.scale, orientation: .up)
    }
}
