import CoreGraphics

/// Automatic placement of photos on a board.
public enum BoardLayout {
    public static let imageHeight: CGFloat = MarkupDocument.boardImageHeight
    public static let gap: CGFloat = 48
    public static let imagesPerRow = 3

    public enum Arrangement: String, CaseIterable, Sendable {
        /// All photos in one row.
        case row
        /// One photo per row, equal widths.
        case column
        /// ⌈√N⌉ photos per row.
        case grid
        /// Default flow (3 per row) in the current reading order.
        case tidy
    }

    /// Side-by-side flow: equal heights, left to right, wrapping after `perRow` photos.
    static func flowFrames(for sizes: [CGSize], perRow: Int = BoardLayout.imagesPerRow, height: CGFloat = BoardLayout.imageHeight, gap: CGFloat = BoardLayout.gap, origin: CGPoint = .zero) -> [CGRect] {
        var frames: [CGRect] = []
        var x = origin.x, y = origin.y
        for (index, size) in sizes.enumerated() {
            if index > 0 && index % max(perRow, 1) == 0 {
                x = origin.x
                y += height + gap
            }
            let aspect = size.height > 0 ? size.width / size.height : 1
            let width = height * aspect
            frames.append(CGRect(x: x, y: y, width: width, height: height))
            x += width + gap
        }
        return frames
    }

    /// One photo per row, all the same width.
    static func columnFrames(for sizes: [CGSize], width: CGFloat = 800, gap: CGFloat = BoardLayout.gap, origin: CGPoint = .zero) -> [CGRect] {
        var frames: [CGRect] = []
        var y = origin.y
        for size in sizes {
            let aspect = size.width > 0 ? size.height / size.width : 1
            let height = width * aspect
            frames.append(CGRect(x: origin.x, y: y, width: width, height: height))
            y += height + gap
        }
        return frames
    }

    static func frames(for sizes: [CGSize], arrangement: Arrangement, origin: CGPoint = .zero) -> [CGRect] {
        switch arrangement {
        case .row:
            return flowFrames(for: sizes, perRow: max(sizes.count, 1), origin: origin)
        case .column:
            return columnFrames(for: sizes, origin: origin)
        case .grid:
            let perRow = max(Int(ceil(sqrt(Double(sizes.count)))), 1)
            return flowFrames(for: sizes, perRow: perRow, origin: origin)
        case .tidy:
            return flowFrames(for: sizes, origin: origin)
        }
    }
}
