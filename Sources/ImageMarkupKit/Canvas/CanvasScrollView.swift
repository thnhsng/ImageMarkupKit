import UIKit

/// The zooming scroll view. Its pan may be vetoed when a touch starts on an item (Select mode),
/// so dragging an item never scrolls the canvas.
final class CanvasScrollView: UIScrollView {
    /// Return `false` to stop the one-finger pan from starting at this point (in the scroll view's coordinates).
    var shouldBeginPan: ((CGPoint) -> Bool)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        delaysContentTouches = false
        contentInsetAdjustmentBehavior = .never
        showsHorizontalScrollIndicator = false
        showsVerticalScrollIndicator = false
        bouncesZoom = true
        decelerationRate = .normal
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === panGestureRecognizer,
           gestureRecognizer.numberOfTouches <= 1,
           let shouldBeginPan,
           !shouldBeginPan(gestureRecognizer.location(in: self)) {
            return false
        }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }
}
