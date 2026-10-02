import UIKit

public extension RGBAColor {
    /// Converts any UIKit color to sRGB. Wide-gamut components (e.g. from the color picker) are clamped.
    init(_ color: UIColor) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1
        if !color.getRed(&r, green: &g, blue: &b, alpha: &a) {
            var white: CGFloat = 0
            if color.getWhite(&white, alpha: &a) {
                r = white; g = white; b = white
            }
        }
        self.init(red: r, green: g, blue: b, alpha: a)
    }

    var uiColor: UIColor { UIColor(red: red, green: green, blue: blue, alpha: alpha) }
}
