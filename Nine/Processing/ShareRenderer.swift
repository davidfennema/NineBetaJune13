import UIKit

enum ShareExportKind: String, Identifiable {
    case grid
    case frame
    case contactSheet

    var id: String { rawValue }

    var actionTitle: String {
        switch self {
        case .grid: "Share Grid"
        case .frame: "Share Frame"
        case .contactSheet: "Share Contact Sheet"
        }
    }
}

struct SharePreviewItem: Identifiable {
    let id = UUID()
    let image: UIImage
    let title: String
    let kind: ShareExportKind
}

enum ShareRenderer {
    static func grid(for roll: Roll, includesAttribution: Bool) -> UIImage? {
        GridRenderer.render(
            images: roll.blendedImages,
            side: 3000,
            attribution: includesAttribution ? "Nine" : nil
        )
    }

    static func frame(_ image: UIImage, includesAttribution: Bool) -> UIImage {
        let square = GridRenderer.squareImage(image)
        guard includesAttribution else { return square }

        let side = max(square.size.width, square.size.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            square.draw(in: CGRect(x: 0, y: 0, width: side, height: side))
            drawAttribution("Nine", side: side, alignment: .right)
        }
    }

    static func contactSheet(for roll: Roll, includesAttribution: Bool) -> UIImage? {
        guard let grid = GridRenderer.render(images: roll.blendedImages, side: 2600) else {
            return nil
        }

        let width: CGFloat = 3000
        let height: CGFloat = 3720
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))

            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 118, weight: .light),
                .foregroundColor: UIColor.white.withAlphaComponent(0.92)
            ]
            let metadataAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 38, weight: .medium),
                .foregroundColor: UIColor.white.withAlphaComponent(0.48),
                .kern: 4
            ]

            roll.title.draw(
                in: CGRect(x: 200, y: 168, width: width - 400, height: 150),
                withAttributes: titleAttributes
            )

            let metadata = "\(roll.createdAt.formatted(date: .abbreviated, time: .shortened).uppercased())   \(roll.mode.title.uppercased())"
            metadata.draw(
                in: CGRect(x: 204, y: 322, width: width - 408, height: 60),
                withAttributes: metadataAttributes
            )

            grid.draw(in: CGRect(x: 200, y: 520, width: 2600, height: 2600))

            if includesAttribution {
                drawAttribution("Created with Nine", side: width, y: height - 180, alignment: .center)
            }
        }
    }

    private static func drawAttribution(
        _ text: String,
        side: CGFloat,
        y: CGFloat? = nil,
        alignment: NSTextAlignment
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: side * 0.0085, weight: .medium),
            .foregroundColor: UIColor.white.withAlphaComponent(0.34),
            .paragraphStyle: paragraph
        ]
        let inset = side * 0.024
        let rect = CGRect(
            x: inset,
            y: y ?? side - inset - side * 0.018,
            width: side - inset * 2,
            height: side * 0.028
        )
        text.draw(in: rect, withAttributes: attributes)
    }
}
