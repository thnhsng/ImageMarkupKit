import CoreGraphics
import Foundation

/// A photo to place on a canvas: its asset key and oriented pixel size.
public struct ImageSource: Equatable, Sendable {
    public var assetID: String
    public var pixelSize: CGSize

    public init(assetID: String, pixelSize: CGSize) {
        self.assetID = assetID
        self.pixelSize = pixelSize
    }
}

public extension MarkupDocument {
    /// One photo to annotate. The photo becomes the locked, clipped background.
    static func imageDocument(_ source: ImageSource) -> MarkupDocument {
        let size = fittedSize(for: source.pixelSize, longEdge: imageLongEdge)
        let background = MarkupItem(
            content: .image(ImageContent(assetID: source.assetID, pixelSize: source.pixelSize, box: Box(frame: CGRect(origin: .zero, size: size)))),
            style: ItemStyle(strokeColor: nil),
            isLocked: true
        )
        return MarkupDocument(kind: .image(backgroundItemID: background.id), backgroundColor: .white, items: [background])
    }

    /// A board with photos placed side by side (equal heights, 3 per row) in the given order.
    static func board(_ sources: [ImageSource]) -> MarkupDocument {
        var document = MarkupDocument(kind: .board, backgroundColor: .white)
        document.appendImages(sources)
        return document
    }

    /// Adds photos after the existing ones, continuing the side-by-side reading order.
    /// Returns the ids of the new image items.
    @discardableResult
    mutating func appendImages(_ sources: [ImageSource]) -> [UUID] {
        guard !sources.isEmpty else { return [] }
        let existing = imageItems.compactMap { $0.box?.frame }
        let allSizes = existing.map(\.size) + sources.map(\.pixelSize)
        let origin = existing.first?.origin ?? .zero
        let frames = BoardLayout.flowFrames(for: allSizes, origin: origin)
        var ids: [UUID] = []
        for (offset, source) in sources.enumerated() {
            var frame = frames[existing.count + offset]
            // When earlier photos were moved by hand, keep new ones below everything instead of on top.
            if existing.contains(where: { $0.intersects(frame) }) {
                let bottom = existing.map(\.maxY).max() ?? 0
                frame.origin = CGPoint(x: origin.x + CGFloat(offset) * (frame.width + BoardLayout.gap), y: bottom + BoardLayout.gap)
            }
            let item = MarkupItem(
                content: .image(ImageContent(assetID: source.assetID, pixelSize: source.pixelSize, box: Box(frame: frame))),
                style: ItemStyle(strokeColor: nil)
            )
            items.append(item)
            ids.append(item.id)
        }
        normalizeZOrder()
        return ids
    }

    /// Board mode: attaches every annotation to the photo under its center, so it follows that photo.
    /// Use after adding annotations programmatically (the editor does this for items drawn by hand).
    mutating func attachAnnotationsToPhotos() {
        self = Attachments.reassigningParents(of: items.filter { !$0.isImage }.map(\.id), in: self)
    }

    /// Canvas-unit size of a photo whose long edge is `longEdge`.
    static func fittedSize(for pixelSize: CGSize, longEdge: CGFloat) -> CGSize {
        guard pixelSize.width > 0, pixelSize.height > 0 else { return CGSize(width: longEdge, height: longEdge) }
        if pixelSize.width >= pixelSize.height {
            return CGSize(width: longEdge, height: longEdge * pixelSize.height / pixelSize.width)
        }
        return CGSize(width: longEdge * pixelSize.width / pixelSize.height, height: longEdge)
    }
}
