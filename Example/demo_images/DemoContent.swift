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

    /// Sample A with one of every annotation kind (image mode, canvas 1024 × 768).
    static func annotatedPhoto() -> (MarkupDocument, AssetCatalog) {
        let samples = samples()
        var document = MarkupDocument.imageDocument(samples.sources[0])
        let red = ItemStyle(strokeColor: .red, lineWidth: 6)
        document.items += [
            .shape(.rectangle, frame: CGRect(x: 150, y: 50, width: 230, height: 190), style: red),
            .shape(.ellipse, frame: CGRect(x: 470, y: 90, width: 230, height: 130), rotation: 0.35,
                   style: ItemStyle(strokeColor: .blue, fillColor: RGBAColor.yellow.withAlpha(0.3), lineWidth: 5)),
            .shape(.triangle, frame: CGRect(x: 760, y: 70, width: 170, height: 150),
                   style: ItemStyle(strokeColor: .green, lineWidth: 6)),
            .shape(.star, frame: CGRect(x: 880, y: 280, width: 110, height: 105),
                   style: ItemStyle(strokeColor: nil, fillColor: .orange, lineWidth: 0)),
            .shape(.speechBubble, frame: CGRect(x: 660, y: 290, width: 190, height: 120),
                   style: ItemStyle(strokeColor: .purple, fillColor: .white, lineWidth: 4)),
            .shape(.highlightBox, frame: CGRect(x: 60, y: 600, width: 330, height: 60),
                   style: StyleDefaults.standard.highlightBox),
            .shape(.rectangle, frame: CGRect(x: 740, y: 520, width: 210, height: 130),
                   style: ItemStyle(strokeColor: .blue, lineWidth: 5, dash: .dashed)),
            .shape(.ellipse, frame: CGRect(x: 560, y: 560, width: 110, height: 110), lockAspect: true,
                   style: ItemStyle(strokeColor: .pink, lineWidth: 6)),
            .stroke(points: wave(from: CGPoint(x: 80, y: 520), to: CGPoint(x: 420, y: 520), amplitude: 22, cycles: 3), style: red),
            .stroke(points: [CGPoint(x: 440, y: 710), CGPoint(x: 600, y: 705), CGPoint(x: 760, y: 712), CGPoint(x: 900, y: 706)],
                    style: StyleDefaults.standard.highlighter, isHighlighter: true),
            .line(from: CGPoint(x: 500, y: 330), to: CGPoint(x: 390, y: 220), style: red),
            .line(from: CGPoint(x: 880, y: 470), to: CGPoint(x: 990, y: 430), startHead: .arrow, endHead: .arrow,
                  style: ItemStyle(strokeColor: .darkGray, lineWidth: 4, dash: .dotted)),
            .text("Crack found / 亀裂あり", at: CGPoint(x: 420, y: 400),
                  font: FontSpec(family: .system, size: 34, bold: true), color: .red, rotation: -0.08),
            .text("Recheck next week\n来週再確認", at: CGPoint(x: 70, y: 300),
                  font: FontSpec(family: .hiraginoSans, size: 26), color: StyleDefaults.standard.noteTextColor,
                  fixedWidth: 300, padding: 16, rotation: 0.05, style: StyleDefaults.standard.note),
        ]
        return (document, samples.catalog)
    }

    /// Samples A, B (EXIF 6) and C side by side with bound connectors and notes.
    static func annotatedBoard() -> (MarkupDocument, AssetCatalog) {
        let samples = samples()
        var document = MarkupDocument.board(Array(samples.sources.prefix(3)))
        let images = document.imageItems
        guard images.count == 3 else { return (document, samples.catalog) }
        let (a, b, c) = (images[0], images[1], images[2])
        let arrowStyle = ItemStyle(strokeColor: .red, lineWidth: 8)

        let circle = MarkupItem.shape(.ellipse, frame: CGRect(x: 110, y: 40, width: 200, height: 280), style: ItemStyle(strokeColor: .red, lineWidth: 8))
        document.items.append(circle)
        document.items.append(.connector(
            from: ConnectorBinding(itemID: a.id, anchor: CGPoint(x: 0.36, y: 0.3)),
            to: ConnectorBinding(itemID: b.id, anchor: CGPoint(x: 0.3, y: 0.45)),
            in: document, style: arrowStyle))
        document.items.append(.connector(
            from: ConnectorBinding(itemID: b.id, anchor: CGPoint(x: 0.75, y: 0.7)),
            to: ConnectorBinding(itemID: c.id, anchor: CGPoint(x: 0.2, y: 0.4)),
            in: document, style: ItemStyle(strokeColor: .blue, lineWidth: 8)))
        document.items.append(.text("Same crack, 2 weeks later\n2週間後の同じ亀裂", at: CGPoint(x: 700, y: -150),
                                    font: FontSpec(family: .hiraginoSans, size: 30), color: StyleDefaults.standard.noteTextColor,
                                    fixedWidth: 380, padding: 16, style: StyleDefaults.standard.note))
        if let cBox = c.box?.frame {
            document.items.append(.shape(.highlightBox, frame: CGRect(x: cBox.minX + 60, y: cBox.minY + 360, width: 520, height: 80),
                                         style: StyleDefaults.standard.highlightBox))
            document.items.append(.text("Leak? / 漏水?", at: CGPoint(x: cBox.minX + 640, y: cBox.minY + 40),
                                        font: FontSpec(family: .system, size: 44, bold: true), color: .red))
        }
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
