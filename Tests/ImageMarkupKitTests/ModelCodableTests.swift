import UIKit
import XCTest
@testable import ImageMarkupKit

final class ModelCodableTests: XCTestCase {
    private func sampleDocument() -> MarkupDocument {
        var document = MarkupDocument.imageDocument(ImageSource(assetID: "a.jpg", pixelSize: CGSize(width: 4032, height: 3024)))
        let shape = MarkupItem.shape(.star, frame: CGRect(x: 10, y: 20, width: 100, height: 80), rotation: 0.4,
                                     style: ItemStyle(strokeColor: .blue, fillColor: .yellow, lineWidth: 3, dash: .dotted, opacity: 0.8, cornerRadius: 4, shadow: true))
        let text = MarkupItem.text("Hello 世界", at: CGPoint(x: 5, y: 5), font: FontSpec(family: .hiraginoMincho, size: 24, bold: true, italic: true),
                                   color: .red, alignment: .center, fixedWidth: 200, padding: 12, rotation: -0.2, style: StyleDefaults.standard.note)
        let stroke = MarkupItem.stroke(points: [CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 40), CGPoint(x: 90, y: 10)], style: StyleDefaults.standard.pen)
        document.items += [shape, text, stroke]
        let line = MarkupItem.connector(from: ConnectorBinding(itemID: shape.id, anchor: CGPoint(x: 0.5, y: 0.5)),
                                        to: ConnectorBinding(itemID: text.id, anchor: CGPoint(x: 0, y: 1)),
                                        in: document, startHead: .arrow, endHead: .arrow, style: StyleDefaults.standard.line)
        document.items.append(line)
        document.items[3].parentID = document.items[0].id
        return document
    }

    func testRoundTripPreservesEveryKind() throws {
        let document = sampleDocument()
        let decoded = try MarkupDocument.decode(from: document.jsonData())
        XCTAssertEqual(decoded, document)
        XCTAssertEqual(decoded.items.map(\.content.typeName), ["image", "shape", "text", "stroke", "line"])
    }

    func testBoardKindRoundTrip() throws {
        let board = MarkupDocument.board([
            ImageSource(assetID: "a", pixelSize: CGSize(width: 400, height: 300)),
            ImageSource(assetID: "b", pixelSize: CGSize(width: 300, height: 400)),
        ])
        let decoded = try MarkupDocument.decode(from: board.jsonData())
        XCTAssertEqual(decoded, board)
        XCTAssertTrue(decoded.isBoard)
    }

    func testUnknownItemTypeIsSkipped() throws {
        let json = """
        {"schemaVersion":1,"id":"11111111-1111-1111-1111-111111111111","kind":"board","items":[
          {"id":"33333333-3333-3333-3333-333333333333","type":"hologram","content":{}},
          {"id":"44444444-4444-4444-4444-444444444444","type":"shape","content":{"kind":"ellipse","box":{"frame":[[0,0],[10,10]]}}}
        ]}
        """
        let document = try MarkupDocument.decode(from: Data(json.utf8))
        XCTAssertEqual(document.items.count, 1)
        XCTAssertEqual(document.items.first?.shapeContent?.kind, .ellipse)
    }

    func testNewerSchemaVersionIsRejected() {
        let json = #"{"schemaVersion":99,"kind":"board","items":[]}"#
        XCTAssertThrowsError(try MarkupDocument.decode(from: Data(json.utf8))) { error in
            XCTAssertEqual(error as? MarkupDecodingError, .unsupportedSchemaVersion(99))
        }
    }

    func testFixtureV1Decodes() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "document_v1", withExtension: "json", subdirectory: "Fixtures"))
        let document = try MarkupDocument.decode(from: Data(contentsOf: url))
        XCTAssertEqual(document.backgroundItemID, UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        XCTAssertEqual(document.items.count, 5, "the unknown 'hologram' item is skipped")
        XCTAssertEqual(document.items[1].style.dash, .dashed)
        XCTAssertEqual(document.items[1].box?.rotation ?? 0, 0.3, accuracy: 1e-9)
        XCTAssertEqual(document.items[2].textContent?.font.family, .hiraginoSans)
        XCTAssertEqual(document.items[2].textContent?.padding, 8, "missing padding falls back to the default")
        XCTAssertEqual(document.items[3].strokeContent?.isHighlighter, true)
        XCTAssertEqual(document.items[4].lineContent?.start.binding?.itemID, UUID(uuidString: "33333333-3333-3333-3333-333333333333"))
        XCTAssertEqual(document.items[4].parentID, document.backgroundItemID)
    }

    func testHexColors() {
        let color = RGBAColor(hex: "#FF000080")
        XCTAssertEqual(color?.red, 1)
        XCTAssertEqual(color?.green, 0)
        XCTAssertEqual(color?.alpha ?? 0, 128.0 / 255.0, accuracy: 1e-9)
        XCTAssertEqual(color?.hexString, "#FF000080")
        XCTAssertEqual(RGBAColor(hex: "00FF00")?.hexString, "#00FF00FF")
        XCTAssertNil(RGBAColor(hex: "#12"))
    }

    func testWideGamutColorsAreClamped() {
        let p3Red = UIColor(displayP3Red: 1, green: 0, blue: 0, alpha: 1)
        let color = RGBAColor(p3Red)
        XCTAssertLessThanOrEqual(color.red, 1)
        XCTAssertGreaterThanOrEqual(color.green, 0)
        XCTAssertGreaterThanOrEqual(color.blue, 0)
    }

    func testZOrderBandsKeepImagesBelowAnnotations() {
        var board = MarkupDocument.board([ImageSource(assetID: "a", pixelSize: CGSize(width: 400, height: 300))])
        board.items.insert(.shape(.rectangle, frame: CGRect(x: 0, y: 0, width: 10, height: 10), style: ItemStyle()), at: 0)
        board.appendImages([ImageSource(assetID: "b", pixelSize: CGSize(width: 400, height: 300))])
        XCTAssertEqual(board.items.map(\.isImage), [true, true, false])
    }
}
