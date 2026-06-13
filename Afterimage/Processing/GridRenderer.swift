import UIKit

enum GridRenderer {
    static func squareImage(_ image: UIImage) -> UIImage {
        guard image.size.width != image.size.height else { return image }
        let side = min(image.size.width, image.size.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
            drawAspectFill(
                image: image,
                in: CGRect(x: 0, y: 0, width: side, height: side),
                context: context.cgContext
            )
        }
    }

    static func render(images: [UIImage], side: CGFloat = 3000, attribution: String? = nil) -> UIImage? {
        guard images.count == Roll.frameCount else { return nil }

        let spacing = side * 0.008
        let inset = side * 0.02
        let cellSide = (side - (inset * 2) - (spacing * 2)) / 3
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))

            for (index, image) in images.map(squareImage).enumerated() {
                let column = index % 3
                let row = index / 3
                let rect = CGRect(
                    x: inset + CGFloat(column) * (cellSide + spacing),
                    y: inset + CGFloat(row) * (cellSide + spacing),
                    width: cellSide,
                    height: cellSide
                )
                drawAspectFill(image: image, in: rect, context: context.cgContext)
            }

            if let attribution {
                drawAttribution(attribution, side: side)
            }
        }
    }

    private static func drawAspectFill(image: UIImage, in rect: CGRect, context: CGContext) {
        context.saveGState()
        context.addRect(rect)
        context.clip()

        let scale = max(rect.width / image.size.width, rect.height / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let destination = CGRect(
            x: rect.midX - size.width / 2,
            y: rect.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        image.draw(in: destination)
        context.restoreGState()
    }

    static func drawAttribution(_ text: String, side: CGFloat) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .right
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: side * 0.0085, weight: .medium),
            .foregroundColor: UIColor.white.withAlphaComponent(0.34),
            .paragraphStyle: paragraph
        ]
        let inset = side * 0.024
        let rect = CGRect(
            x: inset,
            y: side - inset - side * 0.018,
            width: side - inset * 2,
            height: side * 0.018
        )
        text.draw(in: rect, withAttributes: attributes)
    }
}
