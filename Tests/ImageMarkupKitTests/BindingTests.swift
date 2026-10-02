import UIKit
import XCTest
@testable import ImageMarkupKit

final class BindingTests: XCTestCase {
    private func boardWithTwoPhotos() -> MarkupDocument {
        MarkupDocument.board([
            ImageSource(assetID: "a", pixelSize: CGSize(width: 400, height: 300)),
            ImageSource(assetID: "b", pixelSize: CGSize(width: 300, height: 400)),
        ])
    }

    func testAnchorRoundTripOnRotatedTarget() throws {
        var board = boardWithTwoPhotos()
        board.update(board.items[0].id) { $0.box?.rotation = 0.6 }
        let target = board.items[0]
        let box = try XCTUnwrap(target.box)
        let point = box.worldPoint(normalized: CGPoint(x: 0.3, y: 0.8))
        let binding = try XCTUnwrap(Bindings.binding(for: point, on: target, snapDistance: 0))
        XCTAssertEqual(binding.anchor.x, 0.3, accuracy: 1e-9)
        XCTAssertEqual(binding.anchor.y, 0.8, accuracy: 1e-9)
        let resolved = Bindings.resolve(Endpoint(point: .zero, binding: binding), in: board)
        XCTAssertEqual(resolved.x, point.x, accuracy: 1e-9)
        XCTAssertEqual(resolved.y, point.y, accuracy: 1e-9)
    }

    func testBindingSnapsToCenterAndEdgeMidpoints() throws {
        let board = boardWithTwoPhotos()
        let target = board.items[0]
        let center = try XCTUnwrap(target.box?.center)
        let near = center + CGPoint(x: 5, y: -4)
        XCTAssertEqual(Bindings.binding(for: near, on: target, snapDistance: 12)?.anchor, CGPoint(x: 0.5, y: 0.5))
        XCTAssertNotEqual(Bindings.binding(for: near, on: target, snapDistance: 2)?.anchor, CGPoint(x: 0.5, y: 0.5))
    }

    func testBoundEndpointFollowsMoveResizeAndRotate() throws {
        var board = boardWithTwoPhotos()
        let a = board.items[0], b = board.items[1]
        let anchor = CGPoint(x: 0.75, y: 0.25)
        let line = MarkupItem.connector(from: ConnectorBinding(itemID: a.id, anchor: anchor),
                                        to: ConnectorBinding(itemID: b.id, anchor: CGPoint(x: 0.5, y: 0.5)),
                                        in: board, style: ItemStyle())
        board.items.append(line)
        let content = try XCTUnwrap(line.lineContent)

        let mutations: [(inout Box) -> Void] = [
            { $0 = $0.offsetBy(CGPoint(x: 120, y: -40)) },
            { $0.frame.size = CGSize(width: $0.frame.width * 1.5, height: $0.frame.height * 1.5) },
            { $0.rotation = .pi / 3 },
        ]
        for mutate in mutations {
            board.update(a.id) { item in
                var box = item.box!
                mutate(&box)
                item.box = box
            }
            let expected = try XCTUnwrap(board.item(a.id)?.box).worldPoint(normalized: anchor)
            let resolved = Bindings.resolve(content.start, in: board)
            XCTAssertEqual(resolved.x, expected.x, accuracy: 1e-9)
            XCTAssertEqual(resolved.y, expected.y, accuracy: 1e-9)
        }
    }

    func testCachedEndpointsRefreshAfterTargetMoves() throws {
        var board = boardWithTwoPhotos()
        let a = board.items[0]
        let line = MarkupItem.connector(from: ConnectorBinding(itemID: a.id, anchor: CGPoint(x: 0.5, y: 0.5)),
                                        to: ConnectorBinding(itemID: board.items[1].id, anchor: CGPoint(x: 0.5, y: 0.5)),
                                        in: board, style: ItemStyle())
        board.items.append(line)
        board.update(a.id) { $0.box = $0.box?.offsetBy(CGPoint(x: 0, y: 500)) }
        Bindings.refreshCachedEndpoints(in: &board)
        let cached = try XCTUnwrap(board.item(line.id)?.lineContent?.start.point)
        XCTAssertEqual(cached, try XCTUnwrap(board.item(a.id)?.box?.center))
    }

    func testLinesAndBackgroundAreNotBindTargets() {
        var document = MarkupDocument.imageDocument(ImageSource(assetID: "a", pixelSize: CGSize(width: 1000, height: 800)))
        XCTAssertNil(HitTesting.bindTarget(at: CGPoint(x: 500, y: 400), in: document, tolerance: 5), "the background photo is not a target")
        let rect = MarkupItem.shape(.rectangle, frame: CGRect(x: 100, y: 100, width: 100, height: 100), style: ItemStyle())
        let line = MarkupItem.line(from: CGPoint(x: 0, y: 150), to: CGPoint(x: 400, y: 150), style: ItemStyle())
        document.items += [rect, line]
        XCTAssertEqual(HitTesting.bindTarget(at: CGPoint(x: 150, y: 150), in: document, tolerance: 5)?.id, rect.id)
        XCTAssertNil(HitTesting.bindTarget(at: CGPoint(x: 350, y: 150), in: document, tolerance: 5))
    }
}
