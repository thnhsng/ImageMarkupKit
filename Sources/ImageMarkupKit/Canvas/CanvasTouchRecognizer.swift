import UIKit
import UIKit.UIGestureRecognizerSubclass

/// Single-touch recognizer that begins on touch-down (no pan slop), in the spirit of Drawsana's
/// `ImmediatePanGestureRecognizer`, plus what drawing needs:
/// - coalesced and predicted samples for smooth, low-latency strokes;
/// - `shouldTrack` decides at touch-down whether to take the touch (Select mode only takes touches on items);
/// - a second finger within `pinchWindow` cancels the gesture (the user is starting a pinch), later it ends it.
final class CanvasTouchRecognizer: UIGestureRecognizer {
    /// Called on touch-down; return false to fail immediately so the scroll view can take the touch.
    var shouldTrack: ((UITouch) -> Bool)?

    /// Samples since the last `.changed` (in the recognizer's view), oldest first.
    private(set) var samples: [CGPoint] = []
    private(set) var predictedSamples: [CGPoint] = []
    private(set) var startLocation: CGPoint = .zero
    private(set) var currentLocation: CGPoint = .zero
    private(set) var tapCount = 1
    /// True once the touch moved farther than `tapSlop`.
    private(set) var hasMoved = false
    /// True when a second finger cancelled the gesture (a pinch is starting).
    private(set) var wasCancelledBySecondTouch = false
    private(set) var touchType: UITouch.TouchType = .direct

    var tapSlop: CGFloat = 6
    var pinchWindow: TimeInterval = 0.25
    var pinchTravel: CGFloat = 20

    private var trackedTouch: UITouch?
    private var startTime: TimeInterval = 0

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        allowedTouchTypes = [
            NSNumber(value: UITouch.TouchType.direct.rawValue),
            NSNumber(value: UITouch.TouchType.pencil.rawValue),
            NSNumber(value: UITouch.TouchType.indirectPointer.rawValue),
        ]
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if let trackedTouch {
            // A second finger. Early and nearly still: the user is pinching, so drop what was drawn.
            for touch in touches where touch !== trackedTouch { ignore(touch, for: event) }
            guard state == .began || state == .changed else { return }
            let elapsed = event.timestamp - startTime
            let travel = currentLocation.distance(to: startLocation)
            if elapsed < pinchWindow && travel < pinchTravel {
                wasCancelledBySecondTouch = true
                state = .cancelled
            } else {
                state = .ended
            }
            return
        }
        guard touches.count == 1, let touch = touches.first, let view else {
            state = .failed
            return
        }
        if let shouldTrack, !shouldTrack(touch) {
            state = .failed
            return
        }
        trackedTouch = touch
        touchType = touch.type
        startTime = event.timestamp
        tapCount = touch.tapCount
        startLocation = touch.location(in: view)
        currentLocation = startLocation
        samples = [startLocation]
        predictedSamples = []
        state = .began
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let trackedTouch, touches.contains(trackedTouch), let view, state == .began || state == .changed else { return }
        let coalesced = event.coalescedTouches(for: trackedTouch) ?? [trackedTouch]
        samples = coalesced.map { $0.location(in: view) }
        predictedSamples = (event.predictedTouches(for: trackedTouch) ?? []).map { $0.location(in: view) }
        currentLocation = trackedTouch.location(in: view)
        if !hasMoved && currentLocation.distance(to: startLocation) > tapSlop {
            hasMoved = true
        }
        state = .changed
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let trackedTouch, touches.contains(trackedTouch), let view else { return }
        currentLocation = trackedTouch.location(in: view)
        samples = [currentLocation]
        predictedSamples = []
        if state == .began || state == .changed {
            state = .ended
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let trackedTouch, touches.contains(trackedTouch) else { return }
        if state == .began || state == .changed {
            state = .cancelled
        } else {
            state = .failed
        }
    }

    override func reset() {
        super.reset()
        trackedTouch = nil
        samples = []
        predictedSamples = []
        hasMoved = false
        wasCancelledBySecondTouch = false
        tapCount = 1
    }

    /// A touch that went down and up without moving.
    var isTap: Bool { !hasMoved }
}
