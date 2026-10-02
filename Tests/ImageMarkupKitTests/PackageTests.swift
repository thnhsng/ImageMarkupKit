import UIKit
import XCTest
@testable import ImageMarkupKit

final class PackageTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = TestSupport.temporaryDirectory.appendingPathComponent("packages-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func sampleBoard() -> (MarkupDocument, AssetCatalog, [URL]) {
        let a = TestSupport.writeJPEG(width: 400, height: 300, color: .red)
        let b = TestSupport.writeJPEG(width: 300, height: 400, color: .blue)
        var board = MarkupDocument.board([
            ImageSource(assetID: "a.jpg", pixelSize: CGSize(width: 400, height: 300)),
            ImageSource(assetID: "b.jpg", pixelSize: CGSize(width: 300, height: 400)),
        ])
        board.items.append(.connector(from: ConnectorBinding(itemID: board.items[0].id, anchor: CGPoint(x: 0.5, y: 0.5)),
                                      to: ConnectorBinding(itemID: board.items[1].id, anchor: CGPoint(x: 0.5, y: 0.5)),
                                      in: board, style: ItemStyle()))
        board.items.append(.text("点検 OK", at: CGPoint(x: 10, y: -80), font: FontSpec(size: 30), color: .red))
        let catalog = AssetCatalog(urls: ["a.jpg": a, "b.jpg": b, "unused.jpg": a])
        return (board, catalog, [a, b])
    }

    func testSaveAndLoadRoundTrip() throws {
        let (board, catalog, originals) = sampleBoard()
        let rendering = MarkupRenderer.renderSynchronously(board, assets: catalog)
        let url = try MarkupPackage.save(board, assets: catalog, export: rendering, in: directory)
        XCTAssertEqual(url.pathExtension, "markup")

        let contents = try MarkupPackage.load(from: url)
        XCTAssertEqual(contents.document, board)
        XCTAssertEqual(Set(contents.assets.urls.keys), ["a.jpg", "b.jpg"], "unreferenced assets are not copied")
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(contents.assets.url(for: "a.jpg"))), try Data(contentsOf: originals[0]), "photos are stored byte-for-byte")
        XCTAssertNotNil(contents.exportURL)
        XCTAssertNotNil(contents.thumbnailURL)
        let exported = try XCTUnwrap(UIImage(contentsOfFile: XCTUnwrap(contents.exportURL).path))
        XCTAssertEqual(exported.size.width * exported.scale, rendering.pixelSize.width)

        let leftovers = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasPrefix(".staging") }
        XCTAssertTrue(leftovers.isEmpty, "no staging folder is left behind")
    }

    func testResavingFromTheLoadedPackageReplacesIt() throws {
        let (board, catalog, _) = sampleBoard()
        let url = try MarkupPackage.save(board, assets: catalog, export: nil, in: directory)
        let contents = try MarkupPackage.load(from: url)

        // Remove photo B and save again, reading assets from inside the package being replaced.
        var edited = contents.document
        let removed = edited.items[1].id
        edited.items.removeAll { $0.id == removed }
        Bindings.detachReferences(to: [removed], in: &edited)
        let again = try MarkupPackage.save(edited, assets: contents.assets, export: nil, in: directory)
        XCTAssertEqual(again, url, "same document, same package")

        let reloaded = try MarkupPackage.load(from: again)
        XCTAssertEqual(reloaded.document, edited)
        let files = try FileManager.default.contentsOfDirectory(atPath: again.appendingPathComponent("assets").path)
        XCTAssertEqual(files, ["a.jpg"], "photos no longer used are dropped")
        XCTAssertEqual(MarkupPackage.packages(in: directory), [url])
    }

    func testMissingAssetFailsLoudly() {
        let (board, _, _) = sampleBoard()
        XCTAssertThrowsError(try MarkupPackage.save(board, assets: AssetCatalog(), export: nil, in: directory))
    }
}
