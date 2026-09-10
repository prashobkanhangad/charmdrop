import AppKit

/// Draws the menu bar icon in code as a template image: a short cord with a
/// bead hanging from it.
///
/// A template image automatically adapts to light and dark menu bars and to the
/// user's accent and reduced-transparency settings, which a bitmap asset would
/// not do for free.
enum MenuBarIcon {

    static func makeImage(size: CGSize = CGSize(width: 16, height: 16)) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }

            let centerX = rect.midX
            let cordTop = rect.maxY - 1.5
            let beadRadius = rect.width * 0.22
            let beadCenterY = rect.minY + beadRadius + 1.5

            context.setStrokeColor(NSColor.black.cgColor)
            context.setLineWidth(rect.width * 0.09)
            context.setLineCap(.round)
            context.move(to: CGPoint(x: centerX, y: cordTop))
            context.addLine(to: CGPoint(x: centerX, y: beadCenterY + beadRadius * 0.6))
            context.strokePath()

            context.setFillColor(NSColor.black.cgColor)
            context.addEllipse(in: CGRect(
                x: centerX - beadRadius,
                y: beadCenterY - beadRadius,
                width: beadRadius * 2,
                height: beadRadius * 2
            ))
            context.fillPath()

            return true
        }

        image.isTemplate = true
        image.accessibilityDescription = Constants.App.displayName
        return image
    }
}
