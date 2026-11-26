import UIKit
import XCTest
@testable import ImageMarkupKit

/// Speech bubbles whose tail is dragged: geometry, persistence, hit testing, export and the tail handles.
final class BubbleTailTests: XCTestCase {
    private func bubble(_ frame: CGRect, rotation: CGFloat = 0, style: ItemStyle = ItemStyle()) -> MarkupItem {
        .shape(.speechBubble, frame: frame, rotation: rotation, style: style)
    }

    private func withTail(_ item: MarkupItem, _ tail: BubbleTail) -> MarkupItem {
        var item = item
        guard case .shape(var shape) = item.content else { return item }
        shape.tail = tail
        item.content = .shape(shape)
        return item
    }

    /// Every point of an item's outline in world space, element by element.
    private func worldOutline(_ item: MarkupItem) throws -> [CGPoint] {
        let shape = try XCTUnwrap(item.shapeContent)
        var transform = shape.box.boxToWorld
        let path = try XCTUnwrap(PathFactory.shapePath(shape, cornerRadius: item.style.cornerRadius).copy(using: &transform))
        var points: [CGPoint] = []
        path.applyWithBlock { element in
            let count: Int
            switch element.pointee.type {
            case .moveToPoint, .addLineToPoint: count = 1
            case .addQuadCurveToPoint: count = 2
            case .addCurveToPoint: count = 3
            default: count = 0
            }
            for i in 0..<count { points.append(element.pointee.points[i]) }
        }
        return points
    }

    // MARK: Geometry

    func testAdjustingABubbleKeepsItsOutline() throws {
        for size in [CGSize(width: 160, height: 120), CGSize(width: 300, height: 80), CGSize(width: 60, height: 200)] {
            for cornerRadius in [0, 8, 300] as [CGFloat] {
                for rotation in [0, 0.7, 2.45] as [CGFloat] {
                    let original = bubble(CGRect(origin: CGPoint(x: 40, y: 70), size: size), rotation: rotation,
                                          style: ItemStyle(cornerRadius: cornerRadius))
                    let adjusted = try XCTUnwrap(BubbleGeometry.withTail(original))
                    let shape = try XCTUnwrap(adjusted.shapeContent)
                    XCTAssertEqual(shape.tail, BubbleGeometry.originalTail)
                    XCTAssertEqual(shape.box.frame.height, size.height * 0.78, accuracy: 1e-9, "the box is the body")
                    let before = try worldOutline(original), after = try worldOutline(adjusted)
                    XCTAssertEqual(before.count, after.count)
                    for (a, b) in zip(before, after) {
                        XCTAssertEqual(a.distance(to: b), 0, accuracy: 1e-9, "\(size) r=\(cornerRadius) θ=\(rotation)")
                    }
                }
            }
        }
    }

    func testWithTailLeavesOtherItemsAlone() throws {
        XCTAssertNil(BubbleGeometry.withTail(.shape(.rectangle, frame: CGRect(x: 0, y: 0, width: 10, height: 10), style: ItemStyle())))
        let adjusted = withTail(bubble(CGRect(x: 0, y: 0, width: 100, height: 50)), BubbleTail(tip: CGPoint(x: 2, y: 0.5), width: 0.3))
        XCTAssertEqual(BubbleGeometry.withTail(adjusted), adjusted)
    }

    func testTailLeavesTheSideFacingItsTip() throws {
        let size = CGSize(width: 200, height: 100)
        let cases: [(CGPoint, BubbleGeometry.Side)] = [
            (CGPoint(x: 0.4, y: -0.8), .top), (CGPoint(x: 1.6, y: 0.7), .right),
            (CGPoint(x: 0.2, y: 1.5), .bottom), (CGPoint(x: -0.9, y: 0.1), .left),
        ]
        for (tip, side) in cases {
            let layout = try XCTUnwrap(BubbleGeometry.layout(size: size, cornerRadius: 0, tail: BubbleTail(tip: tip, width: 0.2)))
            XCTAssertEqual(layout.side, side, "\(tip)")
            let bounds = BubbleGeometry.path(size: size, cornerRadius: 0, tail: BubbleTail(tip: tip, width: 0.2)).boundingBoxOfPath
            let point = CGPoint(x: tip.x * size.width, y: tip.y * size.height)
            XCTAssertEqual(bounds.union(CGRect(origin: point, size: .zero)), bounds, "the outline reaches the tip")
        }
        XCTAssertNil(BubbleGeometry.layout(size: size, cornerRadius: 0, tail: BubbleTail(tip: CGPoint(x: 0.3, y: 0.6), width: 0.2)),
                     "no tail when the tip is inside the body")
        let inside = BubbleGeometry.path(size: size, cornerRadius: 0, tail: BubbleTail(tip: CGPoint(x: 0.3, y: 0.6), width: 0.2))
        XCTAssertEqual(inside.boundingBoxOfPath, CGRect(origin: .zero, size: size))
    }

    func testBaseStaysOnTheStraightPartOfItsSide() throws {
        let size = CGSize(width: 200, height: 100)
        let layout = try XCTUnwrap(BubbleGeometry.layout(size: size, cornerRadius: 30, tail: BubbleTail(tip: CGPoint(x: -0.6, y: 3), width: 0.9)))
        XCTAssertEqual(layout.side, .bottom)
        XCTAssertEqual(layout.width, 200 - 60, accuracy: 1e-9, "at most the side between its corners")
        XCTAssertEqual(layout.center - layout.width / 2, 30, accuracy: 1e-9)
    }

    func testDraggingTheTailHandles() throws {
        let item = withTail(bubble(CGRect(x: 100, y: 100, width: 200, height: 100)), BubbleTail(tip: CGPoint(x: 0.2, y: 1.5), width: 0.2))
        let tip = try XCTUnwrap(BubbleGeometry.tail(of: item, moving: .tip, to: CGPoint(x: 500, y: 40)))
        XCTAssertEqual(tip.tip.x, 2, accuracy: 1e-9)
        XCTAssertEqual(tip.tip.y, -0.6, accuracy: 1e-9)
        XCTAssertEqual(tip.width, 0.2)

        let layout = try XCTUnwrap(BubbleGeometry.layout(size: CGSize(width: 200, height: 100), cornerRadius: 0, tail: BubbleTail(tip: CGPoint(x: 0.2, y: 1.5), width: 0.2)))
        let center = 100 + layout.center
        XCTAssertEqual(try XCTUnwrap(BubbleGeometry.tail(of: item, moving: .width, to: CGPoint(x: center + 30, y: 250))).width, 0.3, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(BubbleGeometry.tail(of: item, moving: .width, to: CGPoint(x: center, y: 200))).width, BubbleGeometry.minimumWidth)
        let widest = try XCTUnwrap(BubbleGeometry.tail(of: item, moving: .width, to: CGPoint(x: center + 900, y: 200))).width
        XCTAssertEqual(widest, (200 - 2 * layout.radius) / 200, accuracy: 1e-9)
    }

    func testWidthHandleStaysUnderThePointerWhenACornerStopsTheBase() throws {
        // Tip far to the left: the base's middle is stopped by the bottom-left corner (radius 22).
        let item = withTail(bubble(CGRect(x: 0, y: 0, width: 200, height: 100)), BubbleTail(tip: CGPoint(x: -0.6, y: 3), width: 0.4))
        let size = CGSize(width: 200, height: 100)
        let before = try XCTUnwrap(BubbleGeometry.layout(size: size, cornerRadius: 0, tail: try XCTUnwrap(item.shapeContent?.tail)))
        XCTAssertEqual(before.center, 22 + 40, accuracy: 1e-9, "pinned")
        for along in [130, 102, 80, 60] as [CGFloat] {
            let tail = try XCTUnwrap(BubbleGeometry.tail(of: item, moving: .width, to: CGPoint(x: along, y: 100)))
            let after = try XCTUnwrap(BubbleGeometry.layout(size: size, cornerRadius: 0, tail: tail))
            XCTAssertEqual(after.widthHandle.x, along, accuracy: 1e-9, "handle under the pointer at \(along)")
        }
    }

    // MARK: Persistence

    func testBubblesWithoutATailEncodeAsBefore() throws {
        let json = try XCTUnwrap(String(data: JSONEncoder().encode(bubble(CGRect(x: 0, y: 0, width: 100, height: 80))), encoding: .utf8))
        XCTAssertFalse(json.contains("tail"))
    }

    func testTailRoundTrip() throws {
        var doc = MarkupDocument(kind: .board)
        doc.items.append(withTail(bubble(CGRect(x: 10, y: 20, width: 200, height: 100), rotation: 0.3),
                                  BubbleTail(tip: CGPoint(x: 1.4, y: -0.25), width: 0.35)))
        let data = try doc.jsonData()
        XCTAssertTrue(try XCTUnwrap(String(data: data, encoding: .utf8)).contains("\"tail\""))
        XCTAssertEqual(try MarkupDocument.decode(from: data), doc)
    }

    func testUnreadableTailLeavesTheOriginalBubble() throws {
        var doc = MarkupDocument(kind: .board)
        doc.items.append(withTail(bubble(CGRect(x: 10, y: 20, width: 200, height: 100)), BubbleTail(tip: CGPoint(x: 0.5, y: 2), width: 0.2)))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: doc.jsonData()) as? [String: Any])
        let bad: [Any] = ["tail", NSNull(), ["tip": [1, 2]], ["tip": [1], "width": 0.2], ["tip": "x", "width": 0.2], ["tip": [1, 2], "width": "wide"]]
        for value in bad {
            var root = object
            var items = try XCTUnwrap(root["items"] as? [[String: Any]])
            var content = try XCTUnwrap(items[0]["content"] as? [String: Any])
            content["tail"] = value
            items[0]["content"] = content
            root["items"] = items
            let decoded = try MarkupDocument.decode(from: JSONSerialization.data(withJSONObject: root))
            XCTAssertEqual(decoded.items.count, 1, "\(value)")
            XCTAssertNil(decoded.items.first?.shapeContent?.tail, "\(value)")
        }
    }

    // MARK: Hit testing and extent

    func testTheTailPastTheBoxCanBeTouched() throws {
        let filled = withTail(bubble(CGRect(x: 100, y: 100, width: 200, height: 100), style: ItemStyle(strokeColor: nil, fillColor: .white)),
                              BubbleTail(tip: CGPoint(x: 0.5, y: 2.5), width: 0.3))
        let doc = MarkupDocument(kind: .board, items: [filled])
        // Inside the tail, well below the box.
        XCTAssertEqual(HitTesting.item(at: CGPoint(x: 200, y: 300), in: doc, tolerance: 1)?.id, filled.id)
        XCTAssertNil(HitTesting.item(at: CGPoint(x: 120, y: 300), in: doc, tolerance: 1), "beside the tail")

        let bounds = ItemGeometry.visualBounds(of: filled, in: doc)
        XCTAssertEqual(bounds.maxY, 350, accuracy: 1e-9, "visual bounds reach the tip")
        XCTAssertFalse(HitTesting.erasableItems(alongSegment: CGPoint(x: 195, y: 330), CGPoint(x: 205, y: 330), radius: 4, in: doc).isEmpty)
    }

    func testBoardExportIncludesTheTail() {
        var board = MarkupDocument.board([ImageSource(assetID: "a", pixelSize: CGSize(width: 800, height: 600))])
        board.items.append(withTail(bubble(CGRect(x: 500, y: 100, width: 200, height: 100), style: ItemStyle(strokeColor: nil, fillColor: .blue)),
                                    BubbleTail(tip: CGPoint(x: 2, y: 0.5), width: 0.3)))
        let rect = ExportPlanner.exportRect(for: board, options: .default)
        XCTAssertEqual(rect.maxX, 900, accuracy: 1e-9)

        var plain = MarkupDocument(kind: .board, backgroundColor: .white)
        plain.items = board.items.filter { !$0.isImage }
        plain.items[0].style.shadow = true
        let options = MarkupExportOptions(format: .png)
        let plan = ExportPlanner.plan(for: plain, options: options)
        let rendering = MarkupRenderer.renderSynchronously(plain, assets: AssetCatalog(), options: options)
        func pixel(atCanvas p: CGPoint) -> TestSupport.RGBA {
            TestSupport.pixel(rendering.image, x: Int((p.x - plan.rect.minX) * plan.scaleX), y: Int((p.y - plan.rect.minY) * plan.scaleY))
        }
        XCTAssertTrue(pixel(atCanvas: CGPoint(x: 860, y: 150)).isClose(to: .init(r: 0, g: 122, b: 255, a: 255)), "the tail is drawn")
    }

    // MARK: Editing

    @MainActor
    private func makeEditor(with item: MarkupItem) -> MarkupEditorViewController {
        let document = MarkupDocument.imageDocument(ImageSource(assetID: "photo", pixelSize: CGSize(width: 1024, height: 768)))
        let editor = MarkupEditorViewController(document: document, assets: AssetCatalog())
        editor.view.frame = CGRect(x: 0, y: 0, width: 1024, height: 900)
        editor.view.layoutIfNeeded()
        editor.store.perform("Add", select: [item.id]) { $0.items.append(item) }
        editor.refreshOverlay()
        return editor
    }

    @MainActor
    func testOverlayOffersTheTailHandlesFirst() throws {
        let item = bubble(CGRect(x: 300, y: 200, width: 300, height: 200))
        let editor = makeEditor(with: item)
        let overlay = editor.overlayView
        XCTAssertEqual(overlay.handles.prefix(2).map(\.kind), [.bubbleTail(.tip), .bubbleTail(.width)])
        let handles = try XCTUnwrap(BubbleGeometry.handles(of: item))
        XCTAssertEqual(handles.tip.x, 300 + 0.16 * 300, accuracy: 1e-9, "on the tail as drawn")
        XCTAssertEqual(handles.tip.y, 400, accuracy: 1e-9)
        let width = try XCTUnwrap(handles.width)
        XCTAssertEqual(width.x, 300 + 0.42 * 300, accuracy: 1e-9)
        XCTAssertEqual(width.y, 200 + 0.78 * 200, accuracy: 1e-9)
        XCTAssertEqual(overlay.handle(at: editor.canvasView.point(fromCanvas: handles.tip, to: overlay)), .bubbleTail(.tip))

        // Locked bubbles and other shapes have none.
        editor.store.perform("Lock") { $0.update(item.id) { $0.isLocked = true } }
        editor.refreshOverlay()
        XCTAssertTrue(overlay.handles.isEmpty)
        let rect = MarkupItem.shape(.rectangle, frame: CGRect(x: 100, y: 100, width: 200, height: 200), style: ItemStyle())
        editor.store.perform("Add", select: [rect.id]) { $0.items.append(rect) }
        editor.refreshOverlay()
        XCTAssertFalse(overlay.handles.contains { if case .bubbleTail = $0.kind { return true } else { return false } })
    }

    @MainActor
    func testDraggingTheTipAdjustsTheBubbleInOneUndoStep() throws {
        let item = bubble(CGRect(x: 300, y: 200, width: 300, height: 200))
        let editor = makeEditor(with: item)
        let index = editor.document.items.count - 1
        editor.debugPerform(.dragBubbleTail(itemIndex: index, part: .tip, by: CGPoint(x: 400, y: -300)))

        let shape = try XCTUnwrap(editor.document.items[index].shapeContent)
        let tail = try XCTUnwrap(shape.tail)
        // The box shrinks to the body.
        for (value, expected) in zip([shape.box.frame.minX, shape.box.frame.minY, shape.box.frame.width, shape.box.frame.height], [300, 200, 300, 156] as [CGFloat]) {
            XCTAssertEqual(value, expected, accuracy: 1e-9)
        }
        // The tip was at (348, 400); it is now at (748, 100).
        XCTAssertEqual(tail.tip.x, (748 - 300) / 300, accuracy: 1e-9)
        XCTAssertEqual(tail.tip.y, (100 - 200) / 156, accuracy: 1e-9)
        XCTAssertEqual(editor.store.undoManager.undoActionName, "Adjust Tail")

        // The tail now leaves the top side; its width handle is the base's left end. Dragged 30 further left, the
        // handle stays under the pointer although the corner stops the base's middle.
        let widthHandle = try XCTUnwrap(BubbleGeometry.handles(of: editor.document.items[index])?.width)
        editor.debugPerform(.dragBubbleTail(itemIndex: index, part: .width, by: CGPoint(x: -30, y: 0)))
        XCTAssertGreaterThan(try XCTUnwrap(editor.document.items[index].shapeContent?.tail).width, tail.width)
        let moved = try XCTUnwrap(BubbleGeometry.handles(of: editor.document.items[index])?.width)
        XCTAssertEqual(moved.x, widthHandle.x - 30, accuracy: 1e-9)
        XCTAssertEqual(moved.y, widthHandle.y, accuracy: 1e-9)

        editor.undoTapped()
        editor.undoTapped()
        XCTAssertEqual(editor.document.items[index], item, "Undo restores the original bubble")
    }

    @MainActor
    func testArrowsAttachedToABubbleStayWhenItGetsItsTail() throws {
        let item = bubble(CGRect(x: 300, y: 200, width: 300, height: 200))
        let editor = makeEditor(with: item)
        // One end in the tail's strip of the box (below the body), one on the body's right edge.
        var arrow = MarkupItem.line(from: CGPoint(x: 100, y: 100), to: CGPoint(x: 900, y: 600), style: ItemStyle())
        guard case .line(var line) = arrow.content else { return XCTFail() }
        line.start.binding = ConnectorBinding(itemID: item.id, anchor: CGPoint(x: 0.5, y: 0.9))
        line.end.binding = ConnectorBinding(itemID: item.id, anchor: CGPoint(x: 1, y: 0.5))
        arrow.content = .line(line)
        editor.store.perform("Add", select: [item.id]) { $0.items.append(arrow) }
        let before = Bindings.resolvedEndpoints(try XCTUnwrap(editor.document.item(arrow.id)?.lineContent), in: editor.document)

        let index = try XCTUnwrap(editor.document.items.firstIndex { $0.id == item.id })
        editor.debugPerform(.dragBubbleTail(itemIndex: index, part: .tip, by: CGPoint(x: 0, y: 150)))
        XCTAssertNotNil(editor.document.item(item.id)?.shapeContent?.tail)
        let after = Bindings.resolvedEndpoints(try XCTUnwrap(editor.document.item(arrow.id)?.lineContent), in: editor.document)
        XCTAssertEqual(after.start.distance(to: before.start), 0, accuracy: 1e-9)
        XCTAssertEqual(after.end.distance(to: before.end), 0, accuracy: 1e-9)

        editor.undoTapped()
        XCTAssertEqual(editor.document.item(arrow.id)?.lineContent?.start.binding?.anchor, CGPoint(x: 0.5, y: 0.9))
    }

    @MainActor
    func testTailHandlesLeaveLockedBubblesAndTapsAlone() throws {
        var item = bubble(CGRect(x: 300, y: 200, width: 300, height: 200))
        item.isLocked = true
        let editor = makeEditor(with: item)
        let index = editor.document.items.count - 1
        let before = editor.document
        editor.debugPerform(.dragBubbleTail(itemIndex: index, part: .tip, by: CGPoint(x: 100, y: 100)))
        XCTAssertEqual(editor.document, before)

        editor.store.perform("Unlock") { $0.update(item.id) { $0.isLocked = false } }
        let unlocked = editor.document
        editor.debugPerform(.dragBubbleTail(itemIndex: index, part: .tip, by: .zero))
        XCTAssertEqual(editor.document, unlocked, "a tap commits nothing")
    }
}
