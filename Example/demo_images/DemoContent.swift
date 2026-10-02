import UIKit
import ImageMarkupKit

/// Pre-annotated documents built from the sample photos, for demos and screenshots.
enum DemoContent {
    struct Samples {
        var sources: [ImageSource]
        var catalog: AssetCatalog
    }

    /// The sample photos as sources; asset IDs are the file names.
    static func samples() -> Samples {
        var catalog = AssetCatalog()
        var sources: [ImageSource] = []
        for url in SampleImages.urls() {
            guard let metadata = ImageMetadata.read(from: url) else { continue }
            let assetID = url.lastPathComponent
            catalog[assetID] = url
            sources.append(ImageSource(assetID: assetID, pixelSize: metadata.pixelSize))
        }
        return Samples(sources: sources, catalog: catalog)
    }

    /// Sample A (a mountain lake) with one of every annotation kind (image mode, canvas 1024 × 768).
    static func annotatedPhoto() -> (MarkupDocument, AssetCatalog) {
        let samples = samples()
        var document = MarkupDocument.imageDocument(samples.sources[0])
        let red = ItemStyle(strokeColor: .red, lineWidth: 6)
        document.items += [
            // Item 0 is the lodge; the "arrow" demo tool ends on it, so its arrow attaches to it.
            .shape(.rectangle, frame: CGRect(x: 430, y: 655, width: 115, height: 70), style: red),
            .shape(.ellipse, frame: CGRect(x: 365, y: 255, width: 200, height: 95), rotation: -0.08,
                   style: ItemStyle(strokeColor: .blue, fillColor: RGBAColor.yellow.withAlpha(0.25), lineWidth: 5)),
            .shape(.triangle, frame: CGRect(x: 120, y: 560, width: 70, height: 60),
                   style: ItemStyle(strokeColor: .green, lineWidth: 6)),
            .shape(.star, frame: CGRect(x: 865, y: 445, width: 64, height: 62),
                   style: ItemStyle(strokeColor: nil, fillColor: .orange, lineWidth: 0)),
            .shape(.speechBubble, frame: CGRect(x: 720, y: 40, width: 250, height: 120),
                   style: ItemStyle(strokeColor: .purple, fillColor: .white, lineWidth: 4)),
            .shape(.highlightBox, frame: CGRect(x: 40, y: 712, width: 340, height: 46),
                   style: StyleDefaults.standard.highlightBox),
            .shape(.rectangle, frame: CGRect(x: 600, y: 370, width: 175, height: 120),
                   style: ItemStyle(strokeColor: .blue, lineWidth: 5, dash: .dashed)),
            .shape(.ellipse, frame: CGRect(x: 225, y: 425, width: 90, height: 90), lockAspect: true,
                   style: ItemStyle(strokeColor: .pink, lineWidth: 6)),
            // The trail from the lodge to the summit.
            .curve(through: [CGPoint(x: 545, y: 680), CGPoint(x: 610, y: 590), CGPoint(x: 520, y: 490), CGPoint(x: 470, y: 360)],
                   endHead: .arrow, style: ItemStyle(strokeColor: .red, lineWidth: 6, dash: .dashed)),
            .stroke(points: wave(from: CGPoint(x: 50, y: 200), to: CGPoint(x: 330, y: 200), amplitude: 10, cycles: 3), style: red),
            .stroke(points: [CGPoint(x: 580, y: 252), CGPoint(x: 700, y: 249), CGPoint(x: 830, y: 253)],
                    style: StyleDefaults.standard.highlighter, isHighlighter: true),
            .line(from: CGPoint(x: 590, y: 255), to: CGPoint(x: 548, y: 288), style: red),
            .line(from: CGPoint(x: 600, y: 742), to: CGPoint(x: 1000, y: 742), startHead: .arrow, endHead: .arrow,
                  style: ItemStyle(strokeColor: .white, lineWidth: 4, dash: .dotted)),
            .text("Summit 2,456 m", at: CGPoint(x: 575, y: 200),
                  font: FontSpec(family: .system, size: 34, bold: true), color: .red, rotation: -0.05),
            .text("Best view!", at: CGPoint(x: 752, y: 62),
                  font: FontSpec(family: .system, size: 32, bold: true), color: .purple),
            .text("Start 6:00 at the lodge\n山小屋 6:00 出発", at: CGPoint(x: 40, y: 60),
                  font: FontSpec(family: .hiraginoSans, size: 26), color: StyleDefaults.standard.noteTextColor,
                  fixedWidth: 340, padding: 16, rotation: 0.03, style: StyleDefaults.standard.note),
        ]
        return (document, samples.catalog)
    }

    /// Samples A, B (EXIF 6) and C side by side with bound connectors and notes.
    static func annotatedBoard() -> (MarkupDocument, AssetCatalog) {
        let samples = samples()
        var document = MarkupDocument.board(Array(samples.sources.prefix(3)))
        let images = document.imageItems
        guard images.count == 3, let aBox = images[0].box?.frame, let bBox = images[1].box?.frame, let cBox = images[2].box?.frame else {
            return (document, samples.catalog)
        }
        let (a, b, c) = (images[0], images[1], images[2])
        /// A rectangle in a photo's normalized coordinates (fresh boards are unrotated).
        func rect(in box: CGRect, _ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
            CGRect(x: box.minX + box.width * x, y: box.minY + box.height * y, width: box.width * width, height: box.height * height)
        }

        document.items.append(.shape(.ellipse, frame: rect(in: aBox, 0.33, 0.3, 0.23, 0.17), style: ItemStyle(strokeColor: .red, lineWidth: 8)))
        document.items.append(.connector(
            from: ConnectorBinding(itemID: a.id, anchor: CGPoint(x: 0.5, y: 0.38)),
            to: ConnectorBinding(itemID: b.id, anchor: CGPoint(x: 0.3, y: 0.22)),
            in: document, style: ItemStyle(strokeColor: .red, lineWidth: 8)))
        document.items.append(.connector(
            from: ConnectorBinding(itemID: b.id, anchor: CGPoint(x: 0.75, y: 0.6)),
            to: ConnectorBinding(itemID: c.id, anchor: CGPoint(x: 0.62, y: 0.35)),
            in: document, style: ItemStyle(strokeColor: .blue, lineWidth: 8)))
        document.items.append(.text("Summer trip · 3 stops\n夏の旅行・3か所", at: CGPoint(x: bBox.minX, y: bBox.minY - 170),
                                    font: FontSpec(family: .hiraginoSans, size: 30), color: StyleDefaults.standard.noteTextColor,
                                    fixedWidth: 380, padding: 16, style: StyleDefaults.standard.note))
        document.items.append(.shape(.highlightBox, frame: rect(in: cBox, 0.05, 0.78, 0.4, 0.15),
                                     style: StyleDefaults.standard.highlightBox))
        let gamlaStan = rect(in: cBox, 0.08, 0.06, 0, 0).origin
        document.items.append(.text("Gamla Stan", at: gamlaStan, font: FontSpec(family: .system, size: 44, bold: true), color: .red))
        document.attachAnnotationsToPhotos()
        return (document, samples.catalog)
    }

    private static func wave(from start: CGPoint, to end: CGPoint, amplitude: CGFloat, cycles: CGFloat) -> [CGPoint] {
        (0...60).map { i in
            let t = CGFloat(i) / 60
            return CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t + sin(t * cycles * 2 * .pi) * amplitude)
        }
    }
}
