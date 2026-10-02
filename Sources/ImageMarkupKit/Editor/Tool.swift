import Foundation

/// The active tool of the editor.
public enum MarkupTool: Equatable, Sendable {
    case select
    case pen
    case highlighter
    /// Closed shapes. Circle and square are ellipse and rectangle with `lockAspect`.
    case shape(ShapeKind, lockAspect: Bool)
    /// Lines and arrows; endpoints dropped on an item attach to it.
    case arrow
    /// Straight segments through tapped points (Paint's polygon): tap the last point to finish, the first to close.
    case polyline
    /// A line that is bent afterwards by dragging the points it passes through.
    case curve
    case text
    case note
    case eraser

    /// Tools that draw continuously stay active after each use; others return to Select (Preview behavior).
    var staysActiveAfterUse: Bool {
        switch self {
        case .pen, .highlighter, .eraser, .select: return true
        default: return false
        }
    }

    /// Whether a one-finger drag draws (so scrolling needs two fingers).
    var drawsWithOneFinger: Bool { self != .select }
}
