import UIKit
import XCTest
@testable import ImageMarkupKit

final class TransformHitTestTests: XCTestCase {
    private let angles: [CGFloat] = [0, 30, 90, 180, -135].map { $0 * .pi / 180 }

    /// The point opposite the dragged handle must not move, for every handle and rotation.
    func testResizeKeepsAnchorFixed() {
        for angle in angles {
            let box = Box(frame: CGRect(x: 100, y: 100, width: 200, height: 120), rotation: angle)
            for case .resize(let u, let v) in HandleKind.allResize {
                let handleWorld = box.worldPoint(normalized: CGPoint(x: u, y: v))
                let session = ResizeSession(box: box, u: u, v: v, touch: handleWorld, lockAspect: false, minimumSize: 8)
                let drag = CGPoint(x: 37, y: -23).rotated(by: angle)
                let resized = session.box(for: handleWorld + drag)
                let anchor = CGPoint(x: 1 - u, y: 1 - v)
                let before = box.worldPoint(normalized: anchor)
                let after = resized.worldPoint(normalized: anchor)
                XCTAssertEqual(before.x, after.x, accuracy: 1e-6, "u=\(u) v=\(v) angle=\(angle)")
                XCTAssertEqual(before.y, after.y, accuracy: 1e-6, "u=\(u) v=\(v) angle=\(angle)")
                XCTAssertEqual(resized.rotation, angle, accuracy: 1e-12)
            }
        }
    }

    func testResizeFollowsTheHandle() {
        let box = Box(frame: CGRect(x: 0, y: 0, width: 100, height: 100), rotation: 0)
        let session = ResizeSession(box: box, u: 1, v: 1, touch: CGPoint(x: 100, y: 100), lockAspect: false, minimumSize: 8)
        let resized = session.box(for: CGPoint(x: 150, y: 130))
        XCTAssertEqual(resized.frame, CGRect(x: 0, y: 0, width: 150, height: 130))
    }

    func testEdgeHandleChangesOneAxis() {
        let box = Box(frame: CGRect(x: 0, y: 0, width: 100, height: 60), rotation: 0)
        let session = ResizeSession(box: box, u: 1, v: 0.5, touch: CGPoint(x: 100, y: 30), lockAspect: false, minimumSize: 8)
        let resized = session.box(for: CGPoint(x: 140, y: 90))
        XCTAssertEqual(resized.frame.width, 140, accuracy: 1e-9)
        XCTAssertEqual(resized.frame.height, 60, accuracy: 1e-9)
    }

    func testAspectLockedCornerKeepsRatio() {
        let box = Box(frame: CGRect(x: 0, y: 0, width: 400, height: 300), rotation: 0.3)
        let corner = box.worldPoint(normalized: CGPoint(x: 1, y: 1))
        let session = ResizeSession(box: box, u: 1, v: 1, touch: corner, lockAspect: true, minimumSize: 8)
        let resized = session.box(for: corner + CGPoint(x: 80, y: 5))
        XCTAssertEqual(resized.frame.width / resized.frame.height, 4.0 / 3.0, accuracy: 1e-9)
        XCTAssertGreaterThan(resized.frame.width, 400)
    }

    func testResizeClampsInsteadOfFlipping() {
        let box = Box(frame: CGRect(x: 0, y: 0, width: 100, height: 100), rotation: 0)
        let session = ResizeSession(box: box, u: 1, v: 1, touch: CGPoint(x: 100, y: 100), lockAspect: false, minimumSize: 10)
        let resized = session.box(for: CGPoint(x: -300, y: -300))
        XCTAssertEqual(resized.frame, CGRect(x: 0, y: 0, width: 10, height: 10))
    }

    func testTextResizeGrowsDownFromTheTop() {
        let item = MarkupItem.text("A fairly long label that wraps", at: CGPoint(x: 50, y: 50), font: FontSpec(size: 30), color: .red)
        let box = try! XCTUnwrap(item.box)
        let rightMiddle = box.worldPoint(normalized: CGPoint(x: 1, y: 0.5))
        let session = ResizeSession(box: box, u: 1, v: 0.5, touch: rightMiddle, lockAspect: false, minimumSize: 8, anchorsTop: true)
        let narrower = session.box(for: rightMiddle - CGPoint(x: box.frame.width * 0.5, y: 0))
        let resized = TransformMath.resized(item, to: narrower, session: session)
        let text = try! XCTUnwrap(resized.textContent)
        XCTAssertEqual(text.fixedWidth ?? 0, narrower.frame.width, accuracy: 1e-9)
        XCTAssertGreaterThan(text.box.frame.height, box.frame.height, "narrower text wraps onto more lines")
        XCTAssertEqual(text.box.frame.minY, box.frame.minY, accuracy: 1e-6, "top edge stays put")
        XCTAssertEqual(text.box.frame.minX, box.frame.minX, accuracy: 1e-6, "left edge stays put")
    }

    func testRotationSnapsTo45Degrees() {
        let box = Box(frame: CGRect(x: -50, y: -50, width: 100, height: 100), rotation: 0)
        let session = RotateSession(box: box, touch: CGPoint(x: 0, y: -100))
        // Dragging to 43° from the start snaps to 45°.
        let target = CGPoint(x: 0, y: -100).rotated(by: 43 * .pi / 180)
        XCTAssertEqual(session.box(for: target).rotation, .pi / 4, accuracy: 1e-9)
        let free = CGPoint(x: 0, y: -100).rotated(by: 20 * .pi / 180)
        XCTAssertEqual(session.box(for: free).rotation, 20 * .pi / 180, accuracy: 1e-9)
    }

    func testCreationRectAspectLock() {
        XCTAssertEqual(TransformMath.creationRect(from: .zero, to: CGPoint(x: 30, y: -80), lockAspect: true), CGRect(x: 0, y: -80, width: 80, height: 80))
        XCTAssertEqual(TransformMath.creationRect(from: .zero, to: CGPoint(x: 30, y: -80), lockAspect: false), CGRect(x: 0, y: -80, width: 30, height: 80))
    }

    // MARK: Hit testing

    private func document(with items: [MarkupItem]) -> MarkupDocument {
        MarkupDocument(kind: .board, items: items)
    }

    func testRotatedShapeHit() {
        let rect = MarkupItem.shape(.rectangle, frame: CGRect(x: 0, y: 0, width: 200, height: 20), rotation: .pi / 2,
                                    style: ItemStyle(strokeColor: nil, fillColor: .red, lineWidth: 0))
        let doc = document(with: [rect])
        // Rotated 90° about (100, 10): the bar is now vertical.
        XCTAssertNotNil(HitTesting.item(at: CGPoint(x: 100, y: 80), in: doc, tolerance: 1))
        XCTAssertNil(HitTesting.item(at: CGPoint(x: 180, y: 10), in: doc, tolerance: 1))
    }

    func testToleranceScalesWithZoom() {
        let line = MarkupItem.line(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 0), style: ItemStyle(lineWidth: 2))
        let doc = document(with: [line])
        let point = CGPoint(x: 50, y: 9)
        XCTAssertNotNil(HitTesting.item(at: point, in: doc, tolerance: 10 / 1), "zoom 1: 10 pt tolerance reaches")
        XCTAssertNil(HitTesting.item(at: point, in: doc, tolerance: 10 / 4), "zoom 4: 2.5 unit tolerance misses")
    }

    func testUnfilledShapeInsideIsHitOnlyWhenNothingElseIs() {
        let outline = MarkupItem.shape(.rectangle, frame: CGRect(x: 0, y: 0, width: 200, height: 200), style: ItemStyle(lineWidth: 4))
        let dot = MarkupItem.shape(.ellipse, frame: CGRect(x: 90, y: 90, width: 20, height: 20), style: ItemStyle(strokeColor: nil, fillColor: .blue, lineWidth: 0))
        let doc = document(with: [dot, outline])
        XCTAssertEqual(HitTesting.item(at: CGPoint(x: 100, y: 100), in: doc, tolerance: 2)?.id, dot.id, "drawn pixels win over an empty interior on top")
        XCTAssertEqual(HitTesting.item(at: CGPoint(x: 40, y: 150), in: doc, tolerance: 2)?.id, outline.id, "empty interior is grabbable")
    }

    func testTopmostWinsAndBackgroundIsNeverHit() {
        var doc = MarkupDocument.imageDocument(ImageSource(assetID: "a", pixelSize: CGSize(width: 1000, height: 1000)))
        XCTAssertNil(HitTesting.item(at: CGPoint(x: 500, y: 500), in: doc, tolerance: 5), "background photo is not selectable")
        let bottom = MarkupItem.shape(.rectangle, frame: CGRect(x: 0, y: 0, width: 100, height: 100), style: ItemStyle(fillColor: .red))
        let top = MarkupItem.shape(.rectangle, frame: CGRect(x: 50, y: 50, width: 100, height: 100), style: ItemStyle(fillColor: .blue))
        doc.items += [bottom, top]
        XCTAssertEqual(HitTesting.item(at: CGPoint(x: 75, y: 75), in: doc, tolerance: 1)?.id, top.id)
    }

    func testStrokeHitFollowsItsPath() {
        let stroke = MarkupItem.stroke(points: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 100)], style: ItemStyle(lineWidth: 4))
        let doc = document(with: [stroke])
        XCTAssertNotNil(HitTesting.item(at: CGPoint(x: 50, y: 52), in: doc, tolerance: 2))
        XCTAssertNil(HitTesting.item(at: CGPoint(x: 90, y: 10), in: doc, tolerance: 2), "inside the box but far from the stroke")
    }

    func testEraserNeverRemovesPhotosOrLockedItems() {
        var board = MarkupDocument.board([ImageSource(assetID: "a", pixelSize: CGSize(width: 400, height: 300))])
        var locked = MarkupItem.shape(.rectangle, frame: CGRect(x: 10, y: 10, width: 100, height: 100), style: ItemStyle())
        locked.isLocked = true
        let pen = MarkupItem.stroke(points: [CGPoint(x: 0, y: 50), CGPoint(x: 300, y: 50)], style: ItemStyle(lineWidth: 4))
        board.items += [locked, pen]
        let erased = HitTesting.erasableItems(alongSegment: CGPoint(x: 50, y: 0), CGPoint(x: 50, y: 120), radius: 5, in: board)
        XCTAssertEqual(erased, [pen.id])
    }
}
