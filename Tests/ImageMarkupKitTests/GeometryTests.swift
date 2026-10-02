import UIKit
import XCTest
@testable import ImageMarkupKit

final class GeometryTests: XCTestCase {
    func testWorldLocalRoundTrip() {
        let box = Box(frame: CGRect(x: 100, y: 50, width: 200, height: 80), rotation: 0.7)
        for p in [CGPoint(x: 0, y: 0), CGPoint(x: 150, y: 90), CGPoint(x: -40, y: 300)] {
            let back = box.toLocal(box.toWorld(p))
            XCTAssertEqual(back.x, p.x, accuracy: 1e-9)
            XCTAssertEqual(back.y, p.y, accuracy: 1e-9)
        }
    }

    func testNormalizedPointsFollowRotation() {
        let box = Box(frame: CGRect(x: 0, y: 0, width: 200, height: 100), rotation: .pi / 2)
        let center = box.worldPoint(normalized: CGPoint(x: 0.5, y: 0.5))
        XCTAssertEqual(center.x, 100, accuracy: 1e-9)
        XCTAssertEqual(center.y, 50, accuracy: 1e-9)
        // Rotating 90° clockwise (y down) moves the top-left corner to the top-right of the rotated box.
        let topLeft = box.worldPoint(normalized: .zero)
        XCTAssertEqual(topLeft.x, 150, accuracy: 1e-9)
        XCTAssertEqual(topLeft.y, -50, accuracy: 1e-9)
        let normalized = box.normalizedPoint(world: topLeft)
        XCTAssertEqual(normalized.x, 0, accuracy: 1e-9)
        XCTAssertEqual(normalized.y, 0, accuracy: 1e-9)
    }

    func testBoxToWorldMatchesToWorld() {
        let box = Box(frame: CGRect(x: 30, y: 40, width: 120, height: 60), rotation: -0.4)
        let boxPoint = CGPoint(x: 120, y: 0) // top-right in box space
        let viaTransform = boxPoint.applying(box.boxToWorld)
        let viaMethod = box.toWorld(CGPoint(x: box.frame.maxX, y: box.frame.minY))
        XCTAssertEqual(viaTransform.x, viaMethod.x, accuracy: 1e-9)
        XCTAssertEqual(viaTransform.y, viaMethod.y, accuracy: 1e-9)
    }

    func testSmoothedPathForShortInputs() {
        XCTAssertTrue(PathFactory.smoothedPath([]).isEmpty)
        XCTAssertFalse(PathFactory.smoothedPath([CGPoint(x: 5, y: 5)]).boundingBoxOfPath.isNull)
        let two = PathFactory.smoothedPath([.zero, CGPoint(x: 10, y: 0)])
        XCTAssertEqual(two.boundingBoxOfPath.width, 10, accuracy: 1e-9)
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 20), CGPoint(x: 20, y: 0), CGPoint(x: 30, y: 20), CGPoint(x: 40, y: 0)]
        let bounds = PathFactory.smoothedPath(points).boundingBoxOfPath
        let hull = CGRect.bounding(points)
        XCTAssertTrue(hull.insetBy(dx: -0.001, dy: -0.001).contains(bounds), "curves stay inside the control polygon")
    }

    func testSimplifyKeepsEndpointsAndDropsCollinearPoints() {
        let line = (0...100).map { CGPoint(x: CGFloat($0), y: 2 * CGFloat($0)) }
        let simplified = GeometryMath.simplify(line, epsilon: 0.5)
        XCTAssertEqual(simplified, [line.first!, line.last!])
        let zigzag = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 10), CGPoint(x: 20, y: 0)]
        XCTAssertEqual(GeometryMath.simplify(zigzag, epsilon: 0.5), zigzag)
    }

    func testStraightStrokeHasUsableBox() {
        let item = MarkupItem.stroke(points: [CGPoint(x: 0, y: 50), CGPoint(x: 100, y: 50)], style: ItemStyle(lineWidth: 6))
        let stroke = try! XCTUnwrap(item.strokeContent)
        XCTAssertGreaterThanOrEqual(stroke.box.frame.height, 6)
        for p in stroke.points {
            XCTAssertTrue(p.x.isFinite && p.y.isFinite)
            XCTAssertTrue((0...1).contains(p.x) && (0...1).contains(p.y))
        }
        let denormalized = PathFactory.strokePoints(stroke).map { $0 + stroke.box.frame.origin }
        XCTAssertEqual(denormalized.first!.x, 0, accuracy: 1e-9)
        XCTAssertEqual(denormalized.first!.y, 50, accuracy: 1e-9)
    }

    func testTextMeasuring() {
        let base = TextContent(text: "Crack", font: FontSpec(size: 30), color: .red, box: Box(frame: .zero))
        var longer = base
        longer.text = "Crack along the whole beam"
        XCTAssertGreaterThan(TextLayout.measuredSize(for: longer).width, TextLayout.measuredSize(for: base).width)

        var fixed = longer
        fixed.fixedWidth = 120
        let fixedSize = TextLayout.measuredSize(for: fixed)
        XCTAssertEqual(fixedSize.width, 120)
        XCTAssertGreaterThan(fixedSize.height, TextLayout.measuredSize(for: longer).height, "wrapping adds lines")

        var japanese = base
        japanese.text = "亀裂あり、来週再確認"
        japanese.font = FontSpec(family: .hiraginoSans, size: 30)
        let size = TextLayout.measuredSize(for: japanese)
        XCTAssertGreaterThan(size.width, 30 * 5)

        var empty = base
        empty.text = ""
        XCTAssertGreaterThan(TextLayout.measuredSize(for: empty).height, 30, "empty text measures as one line")
    }

    func testFittedTextKeepsTopLeftCorner() {
        let box = Box(frame: CGRect(x: 100, y: 100, width: 10, height: 10), rotation: 0.5)
        let content = TextContent(text: "Some longer text", font: FontSpec(size: 30), color: .red, box: box)
        let fitted = TextLayout.fitted(content)
        let before = box.toWorld(box.frame.origin)
        let after = fitted.box.toWorld(fitted.box.frame.origin)
        XCTAssertEqual(before.x, after.x, accuracy: 1e-6)
        XCTAssertEqual(before.y, after.y, accuracy: 1e-6)
        XCTAssertGreaterThan(fitted.box.frame.width, 10)
    }

    func testShapePathsFillTheirBox() {
        let size = CGSize(width: 200, height: 100)
        for kind in ShapeKind.allCases where kind != .speechBubble {
            let bounds = PathFactory.shapePath(kind: kind, size: size, cornerRadius: 0).boundingBoxOfPath
            XCTAssertEqual(bounds.width, 200, accuracy: 0.5, "\(kind)")
            XCTAssertEqual(bounds.height, 100, accuracy: 0.5, "\(kind)")
        }
    }

    func testArrowHeadsShrinkOnShortLines() {
        let geometry = PathFactory.lineGeometry(start: .zero, end: CGPoint(x: 10, y: 0), lineWidth: 10, startHead: .arrow, endHead: .arrow)
        let heads = try! XCTUnwrap(geometry.heads).boundingBoxOfPath
        XCTAssertLessThanOrEqual(heads.width, 10.001)
    }

    func testBoardFlowLayout() {
        let sizes = [CGSize(width: 400, height: 300), CGSize(width: 300, height: 400), CGSize(width: 800, height: 300), CGSize(width: 400, height: 400)]
        let frames = BoardLayout.flowFrames(for: sizes)
        XCTAssertEqual(frames.map(\.height), [600, 600, 600, 600])
        XCTAssertEqual(frames[0].minY, frames[2].minY, "first three share a row")
        XCTAssertGreaterThan(frames[3].minY, frames[0].maxY, "fourth wraps to the next row")
        XCTAssertEqual(frames[3].minX, frames[0].minX)
        for i in frames.indices {
            for j in frames.indices where j > i {
                XCTAssertFalse(frames[i].intersects(frames[j]), "\(i) overlaps \(j)")
            }
        }
    }
}
