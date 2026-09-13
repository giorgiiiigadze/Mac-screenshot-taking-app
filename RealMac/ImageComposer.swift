import AppKit
import ImageIO
import UniformTypeIdentifiers

enum CameraCorner: String, Codable, CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight

    var label: String {
        switch self {
        case .topLeft: "Top left"
        case .topRight: "Top right"
        case .bottomLeft: "Bottom left"
        case .bottomRight: "Bottom right"
        }
    }
}

enum ImageComposer {
    static func compose(screen: CGImage, reaction: CGImage, corner: CameraCorner = .topRight) throws -> NSImage {
        let width = screen.width
        let height = screen.height
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw CaptureError.photoUnavailable }

        context.interpolationQuality = .high
        context.draw(screen, in: CGRect(x: 0, y: 0, width: width, height: height))

        let margin = max(28, CGFloat(width) * 0.025)
        let overlayWidth = CGFloat(width) * 0.25
        let overlayHeight = overlayWidth * 4 / 3
        let overlayRect = overlayRect(
            corner: corner,
            canvas: CGSize(width: width, height: height),
            overlay: CGSize(width: overlayWidth, height: overlayHeight),
            margin: margin
        )
        let radius = overlayWidth * 0.08

        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -8), blur: 24, color: NSColor.black.withAlphaComponent(0.45).cgColor)
        context.setFillColor(NSColor.white.cgColor)
        context.addPath(CGPath(roundedRect: overlayRect.insetBy(dx: -3, dy: -3), cornerWidth: radius + 3, cornerHeight: radius + 3, transform: nil))
        context.fillPath()
        context.restoreGState()

        context.saveGState()
        context.addPath(CGPath(roundedRect: overlayRect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.clip()
        context.translateBy(x: overlayRect.midX, y: 0)
        context.scaleBy(x: -1, y: 1)
        let mirroredRect = CGRect(x: -overlayRect.width / 2, y: overlayRect.minY, width: overlayRect.width, height: overlayRect.height)
        context.draw(reaction, in: aspectFillRect(image: reaction, destination: mirroredRect))
        context.restoreGState()

        guard let result = context.makeImage() else { throw CaptureError.photoUnavailable }
        return NSImage(cgImage: result, size: NSSize(width: width, height: height))
    }

    static func jpegData(for image: NSImage) throws -> Data {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw CaptureError.photoUnavailable
        }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw CaptureError.photoUnavailable
        }
        CGImageDestinationAddImage(destination, cgImage, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CaptureError.photoUnavailable }
        return data as Data
    }

    static func jpegData(for image: CGImage) throws -> Data {
        try jpegData(for: NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height)))
    }

    private static func aspectFillRect(image: CGImage, destination: CGRect) -> CGRect {
        let sourceRatio = CGFloat(image.width) / CGFloat(image.height)
        let destinationRatio = destination.width / destination.height
        if sourceRatio > destinationRatio {
            let width = destination.height * sourceRatio
            return CGRect(x: destination.midX - width / 2, y: destination.minY, width: width, height: destination.height)
        }
        let height = destination.width / sourceRatio
        return CGRect(x: destination.minX, y: destination.midY - height / 2, width: destination.width, height: height)
    }

    private static func overlayRect(corner: CameraCorner, canvas: CGSize, overlay: CGSize, margin: CGFloat) -> CGRect {
        let x: CGFloat
        let y: CGFloat
        switch corner {
        case .topLeft:
            x = margin
            y = canvas.height - overlay.height - margin
        case .topRight:
            x = canvas.width - overlay.width - margin
            y = canvas.height - overlay.height - margin
        case .bottomLeft:
            x = margin
            y = margin
        case .bottomRight:
            x = canvas.width - overlay.width - margin
            y = margin
        }
        return CGRect(origin: CGPoint(x: x, y: y), size: overlay)
    }
}
