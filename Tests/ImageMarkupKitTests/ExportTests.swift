import UIKit
import XCTest
@testable import ImageMarkupKit

final class ExportTests: XCTestCase {
    func testImageModeExportKeepsOriginalPixelSize() throws {
        let url = TestSupport.writeJPEG(width: 1200, height: 900)
        let metadata = try XCTUnwrap(ImageMetadata.read(from: url))
        var document = MarkupDocument.imageDocument(ImageSource(assetID: "photo", pixelSize: metadata.pixelSize))
        document.items.append(.shape(.rectangle, frame: CGRect(x: 10, y: 10, width: 100, height: 100), style: ItemStyle()))
        let rendering = MarkupRenderer.renderSynchronously(document, assets: AssetCatalog(urls: ["photo": url]))
        XCTAssertEqual(rendering.pixelSize, CGSize(width: 1200, height: 900))
        XCTAssertEqual(rendering.image.size.width * rendering.image.scale, 1200)
        XCTAssertEqual(rendering.image.size.height * rendering.image.scale, 900)
        XCTAssertNotNil(UIImage(data: rendering.data), "JPEG data decodes")
    }

    func testExifOrientationSwapsPixelSize() throws {
        let url = TestSupport.writeJPEG(width: 400, height: 300, orientation: 6)
        let metadata = try XCTUnwrap(ImageMetadata.read(from: url))
        XCTAssertEqual(metadata.orientation, 6)
        XCTAssertEqual(metadata.pixelSize, CGSize(width: 300, height: 400))
        let image = try XCTUnwrap(ImagePipeline.downsample(at: url, maxPixelSize: 1000))
        XCTAssertEqual(image.width, 300)
        XCTAssertEqual(image.height, 400)
    }

    func testLargePhotoIsClampedToMaxDimension() {
        let document = MarkupDocument.imageDocument(ImageSource(assetID: "huge", pixelSize: CGSize(width: 20000, height: 15000)))
        let plan = ExportPlanner.plan(for: document, options: .default)
        XCTAssertTrue(plan.isClamped)
        XCTAssertLessThanOrEqual(max(plan.pixelSize.width, plan.pixelSize.height), 8192)
        XCTAssertLessThanOrEqual(plan.pixelSize.width * plan.pixelSize.height, 40_000_000)
        XCTAssertEqual(plan.pixelSize.width / plan.pixelSize.height, 20000.0 / 15000.0, accuracy: 0.01)
    }

    func testBoardPixelBudget() {
        let sources = (0..<9).map { ImageSource(assetID: "\($0)", pixelSize: CGSize(width: 8000, height: 6000)) }
        let plan = ExportPlanner.plan(for: .board(sources), options: .default)
        XCTAssertLessThanOrEqual(plan.pixelSize.width * plan.pixelSize.height, 40_000_000 + 20_000)
        XCTAssertLessThanOrEqual(max(plan.pixelSize.width, plan.pixelSize.height), 8192)
    }

    func testBoardRectIsUnionOfVisualBoundsPlusPadding() {
        var board = MarkupDocument.board([ImageSource(assetID: "a", pixelSize: CGSize(width: 800, height: 600))])
        board.items.append(.shape(.rectangle, frame: CGRect(x: 900, y: 100, width: 100, height: 100), style: ItemStyle(lineWidth: 6)))
        let rect = ExportPlanner.exportRect(for: board, options: .default)
        XCTAssertEqual(rect, CGRect(x: -24, y: -24, width: 1003 + 48, height: 648))
    }

    func testPixelsLandWhereExpected() {
        var board = MarkupDocument(kind: .board, backgroundColor: .white)
        board.items.append(.shape(.rectangle, frame: CGRect(x: 0, y: 0, width: 100, height: 100),
                                  style: ItemStyle(strokeColor: nil, fillColor: .red, lineWidth: 0)))
        // A square rotated 45° around (300, 50): its center is filled, its original corner is not.
        board.items.append(.shape(.rectangle, frame: CGRect(x: 250, y: 0, width: 100, height: 100), rotation: .pi / 4,
                                  style: ItemStyle(strokeColor: nil, fillColor: .blue, lineWidth: 0)))
        let options = MarkupExportOptions(format: .png)
        let plan = ExportPlanner.plan(for: board, options: options)
        let rendering = MarkupRenderer.renderSynchronously(board, assets: AssetCatalog(), options: options)
        func pixel(atCanvas p: CGPoint) -> TestSupport.RGBA {
            let x = Int((p.x - plan.rect.minX) * plan.scaleX)
            let y = Int((p.y - plan.rect.minY) * plan.scaleY)
            return TestSupport.pixel(rendering.image, x: x, y: y)
        }
        XCTAssertTrue(pixel(atCanvas: CGPoint(x: 50, y: 50)).isClose(to: .init(r: 255, g: 59, b: 48, a: 255)))
        XCTAssertTrue(pixel(atCanvas: CGPoint(x: 300, y: 50)).isClose(to: .init(r: 0, g: 122, b: 255, a: 255)))
        XCTAssertTrue(pixel(atCanvas: CGPoint(x: 253, y: 3)).isClose(to: .init(r: 255, g: 255, b: 255, a: 255)), "corner of the unrotated square is empty")
        XCTAssertTrue(pixel(atCanvas: CGPoint(x: 180, y: 50)).isClose(to: .init(r: 255, g: 255, b: 255, a: 255)))
    }

    func testImageItemIsDrawnFromItsAsset() throws {
        let url = TestSupport.writeJPEG(width: 200, height: 100, color: .green)
        let board = MarkupDocument.board([ImageSource(assetID: "g", pixelSize: CGSize(width: 200, height: 100))])
        let options = MarkupExportOptions(format: .png)
        let plan = ExportPlanner.plan(for: board, options: options)
        let rendering = MarkupRenderer.renderSynchronously(board, assets: AssetCatalog(urls: ["g": url]), options: options)
        let frame = try XCTUnwrap(board.items.first?.box?.frame)
        let x = Int((frame.midX - plan.rect.minX) * plan.scaleX)
        let y = Int((frame.midY - plan.rect.minY) * plan.scaleY)
        let color = TestSupport.pixel(rendering.image, x: x, y: y)
        XCTAssertLessThan(color.r, 60)
        XCTAssertGreaterThan(color.g, 200)
    }
}
