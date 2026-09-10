import CoreGraphics
import Foundation

/// Generates simple original vector artwork for each built-in charm.
///
/// Placeholders are drawn in code rather than shipped as image files so the
/// repository carries no third-party or licensed artwork. When real assets are
/// added to the bundle under the charm's `assetName`, `CharmRenderer` prefers
/// them and this provider is never consulted.
struct PlaceholderCharmArtwork: CharmArtworkProviding {

    func image(for charm: Charm, variant: CharmArtworkVariant, pixelScale: CGFloat) -> CGImage? {
        let variant = charm.supportedVariant(variant)
        let scale = max(1, pixelScale)
        let size = charm.visualSize
        let pixelWidth = Int((size.width * scale).rounded())
        let pixelHeight = Int((size.height * scale).rounded())

        guard pixelWidth > 0, pixelHeight > 0,
              let context = CGContext(
                data: nil,
                width: pixelWidth,
                height: pixelHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }

        context.scaleBy(x: scale, y: scale)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        // Bitmap contexts are y-up, matching the rest of the app's coordinate
        // convention, so the charm's hanging point is at the top: y == height.
        switch charm.id {
        case "nazar": drawNazar(in: context, size: size)
        case "bell": drawBell(in: context, size: size)
        case "diya": drawDiya(in: context, size: size, isLit: variant == .alternate)
        default: drawNimbuMirchi(in: context, size: size, isFresh: variant == .alternate)
        }

        return context.makeImage()
    }

    // MARK: - Charms

    /// `isFresh` is the alternate variant: a newly hung charm, brighter and
    /// more saturated than one that has dried out.
    ///
    /// Composition follows the real totem — chillies threaded in an overlapping
    /// stack with the lemon hanging beneath them — and everything is lit from
    /// the upper left, matching the drop shadow the overlay's charm layer
    /// already casts.
    private func drawNimbuMirchi(in context: CGContext, size: CGSize, isFresh: Bool) {
        let width = size.width
        let height = size.height

        let chilliPalette = isFresh ? ChilliPalette.fresh : ChilliPalette.dried
        let lemonPalette = isFresh ? LemonPalette.fresh : LemonPalette.dried

        drawThread(in: context, size: size, to: height * 0.90)

        // Alternating tip direction gives the totem its zig-zag silhouette.
        // Drawn top to bottom so each chilli overlaps the one above it, which
        // makes the stack cascade toward the viewer instead of looking flat.
        let stack: [(
            y: CGFloat,
            tilt: CGFloat,
            pointsRight: Bool,
            length: CGFloat,
            thickness: CGFloat,
            bend: CGFloat
        )] = [
            (0.860, 0.10, true, 0.52, 0.094, 0.030),
            (0.805, 0.06, false, 0.60, 0.102, 0.038),
            (0.750, 0.09, true, 0.66, 0.108, -0.028),
            (0.695, 0.05, false, 0.70, 0.112, 0.040),
            (0.640, 0.08, true, 0.68, 0.110, -0.030),
            (0.585, 0.06, false, 0.62, 0.104, 0.036),
            (0.530, 0.09, true, 0.56, 0.098, -0.026),
            (0.478, 0.07, false, 0.50, 0.092, 0.032)
        ]

        for (index, chilli) in stack.enumerated() {
            drawChilli(
                in: context,
                center: CGPoint(x: width * 0.5, y: height * chilli.y),
                length: width * chilli.length,
                thickness: width * chilli.thickness,
                tilt: chilli.tilt,
                pointsRight: chilli.pointsRight,
                bend: width * chilli.bend,
                recession: 1 - CGFloat(index) / CGFloat(stack.count - 1),
                palette: chilliPalette
            )
        }

        drawLemon(
            in: context,
            center: CGPoint(x: width * 0.5, y: height * 0.235),
            radius: width * 0.252,
            palette: lemonPalette
        )
    }

    /// One chilli, drawn in a local space with the base at `-length/2` and the
    /// tip pointing along `+x`.
    ///
    /// Two details do most of the work. The tube is shaded across its short
    /// axis rather than along its length, which is what makes it read as round
    /// instead of as a flat leaf; and a left-pointing chilli is *mirrored*
    /// rather than rotated by 180 degrees, so its lit edge stays on top no
    /// matter which way the tip faces.
    ///
    /// `tilt` always raises the tip, whichever direction it points.
    /// `recession` darkens the chilli toward the back of the stack, from 0 at
    /// the front to 1 at the rear.
    private func drawChilli(
        in context: CGContext,
        center: CGPoint,
        length: CGFloat,
        thickness: CGFloat,
        tilt: CGFloat,
        pointsRight: Bool,
        bend: CGFloat,
        recession: CGFloat,
        palette: ChilliPalette
    ) {
        context.saveGState()
        defer { context.restoreGState() }

        context.translateBy(x: center.x, y: center.y)
        context.rotate(by: pointsRight ? tilt : -tilt)
        if !pointsRight {
            context.scaleBy(x: -1, y: 1)
        }

        let halfLength = length / 2
        let halfThickness = thickness / 2
        let baseX = -halfLength
        let tip = CGPoint(x: halfLength, y: bend)

        // A chilli is plump for the first half and then tapers to a fine point,
        // so the belly sits around 40% of the length rather than the middle.
        // Starting and ending the outline at the base *centre* rounds the cap
        // off; a straight edge there would read as a cut cylinder.
        let belly = baseX + length * 0.32
        let shoulder = baseX + length * 0.68

        let body = CGMutablePath()
        body.move(to: CGPoint(x: baseX, y: 0))
        body.addCurve(
            to: CGPoint(x: belly, y: halfThickness * 0.98 + bend * 0.14),
            control1: CGPoint(x: baseX + length * 0.01, y: halfThickness * 1.02),
            control2: CGPoint(x: baseX + length * 0.17, y: halfThickness * 1.02)
        )
        body.addCurve(
            to: tip,
            control1: CGPoint(x: shoulder, y: halfThickness * 0.80 + bend * 0.52),
            control2: CGPoint(x: baseX + length * 0.94, y: halfThickness * 0.30 + bend * 0.88)
        )
        body.addCurve(
            to: CGPoint(x: belly, y: -halfThickness * 0.96 + bend * 0.14),
            control1: CGPoint(x: baseX + length * 0.94, y: -halfThickness * 0.28 + bend * 0.88),
            control2: CGPoint(x: shoulder, y: -halfThickness * 0.78 + bend * 0.52)
        )
        body.addCurve(
            to: CGPoint(x: baseX, y: 0),
            control1: CGPoint(x: baseX + length * 0.17, y: -halfThickness * 1.00),
            control2: CGPoint(x: baseX + length * 0.01, y: -halfThickness * 1.00)
        )
        body.closeSubpath()

        // Stem first, so the body covers the join.
        context.setStrokeColor(palette.stem)
        context.setLineWidth(max(0.5, thickness * 0.20))
        context.move(to: CGPoint(x: baseX + thickness * 0.20, y: 0))
        context.addQuadCurve(
            to: CGPoint(x: baseX - length * 0.085, y: thickness * 0.62),
            control: CGPoint(x: baseX - length * 0.075, y: 0)
        )
        context.strokePath()

        // Flat fill carrying the contact shadow onto whatever sits behind.
        context.saveGState()
        context.setShadow(
            offset: CGSize(width: thickness * 0.08, height: -thickness * 0.20),
            blur: thickness * 0.40,
            color: Palette.contactShadow
        )
        context.addPath(body)
        context.setFillColor(palette.mid)
        context.fillPath()
        context.restoreGState()

        // Cross-tube shading: dark underside up to a lit crest.
        drawLinearGradient(
            in: context,
            clippingTo: [body],
            colors: [palette.shadowEdge, palette.dark, palette.mid, palette.light],
            locations: [0, 0.20, 0.60, 1],
            from: CGPoint(x: 0, y: -halfThickness),
            to: CGPoint(x: 0, y: halfThickness * 1.04)
        )

        // Gloss streak along the crest, fading out at both ends so it reads as
        // a reflection rather than a painted stripe.
        let glossStart = baseX + length * 0.16
        let glossEnd = baseX + length * 0.76
        let glossY = halfThickness * 0.40
        let gloss = CGMutablePath()
        gloss.move(to: CGPoint(x: glossStart, y: glossY))
        gloss.addQuadCurve(
            to: CGPoint(x: glossEnd, y: glossY + bend * 0.6),
            control: CGPoint(x: (glossStart + glossEnd) / 2, y: glossY + halfThickness * 0.46)
        )
        gloss.addQuadCurve(
            to: CGPoint(x: glossStart, y: glossY),
            control: CGPoint(x: (glossStart + glossEnd) / 2, y: glossY + halfThickness * 0.04)
        )
        gloss.closeSubpath()

        drawLinearGradient(
            in: context,
            clippingTo: [body, gloss],
            colors: [Palette.clear, Palette.glossSoft, Palette.glossBright, Palette.clear],
            locations: [0, 0.28, 0.58, 1],
            from: CGPoint(x: glossStart, y: 0),
            to: CGPoint(x: glossEnd, y: 0)
        )

        // Chillies further back in the stack sit in the shade of the ones in
        // front, which is what keeps eight overlapping pods from flattening
        // into one green mass.
        if recession > 0 {
            context.saveGState()
            context.addPath(body)
            context.clip()
            context.setFillColor(palette.shadowEdge.copy(alpha: recession * 0.20) ?? palette.shadowEdge)
            context.fill(body.boundingBoxOfPath)
            context.restoreGState()
        }

        // Ink outline keeps the shape legible at menu-bar size.
        context.addPath(body)
        context.setStrokeColor(palette.outline)
        context.setLineWidth(max(0.5, thickness * 0.10))
        context.strokePath()
    }

    /// A lemon rendered as a lit sphere: radial falloff from an upper-left key
    /// light, bounced light on the shaded rim so it does not go dead, and an
    /// occlusion band where the chillies rest on top.
    private func drawLemon(
        in context: CGContext,
        center: CGPoint,
        radius: CGFloat,
        palette: LemonPalette
    ) {
        let bounds = CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        let body = CGPath(ellipseIn: bounds, transform: nil)

        context.saveGState()
        context.setShadow(
            offset: CGSize(width: radius * 0.05, height: -radius * 0.10),
            blur: radius * 0.28,
            color: Palette.contactShadow
        )
        context.addPath(body)
        context.setFillColor(palette.mid)
        context.fillPath()
        context.restoreGState()

        // Key light. The focus sits off-centre, which is what turns a flat
        // disc into a sphere.
        let keyLight = CGPoint(x: center.x - radius * 0.36, y: center.y + radius * 0.34)
        drawRadialGradient(
            in: context,
            clippingTo: [body],
            colors: [palette.specular, palette.light, palette.mid, palette.dark, palette.shadowEdge],
            locations: [0, 0.26, 0.60, 0.87, 1],
            focus: keyLight,
            center: center,
            radius: radius * 1.44
        )

        // Bounced light along the lower-right rim.
        let bounce = CGPoint(x: center.x + radius * 0.54, y: center.y - radius * 0.58)
        drawRadialGradient(
            in: context,
            clippingTo: [body],
            colors: [palette.rimLight, Palette.fading(palette.rimLight)],
            locations: [0, 1],
            focus: bounce,
            center: bounce,
            radius: radius * 0.92
        )

        // Occlusion where the chilli stack sits on the fruit.
        drawLinearGradient(
            in: context,
            clippingTo: [body],
            colors: [palette.occlusion, Palette.fading(palette.occlusion)],
            locations: [0, 1],
            from: CGPoint(x: center.x, y: center.y + radius),
            to: CGPoint(x: center.x, y: center.y + radius * 0.10)
        )

        // Broad sheen, then a tighter glint inside it.
        let sheen = CGPath(
            ellipseIn: CGRect(
                x: center.x - radius * 0.70,
                y: center.y + radius * 0.04,
                width: radius * 0.66,
                height: radius * 0.86
            ),
            transform: nil
        )
        let sheenBox = sheen.boundingBoxOfPath
        drawRadialGradient(
            in: context,
            clippingTo: [body, sheen],
            colors: [Palette.glossSoft, Palette.clear],
            locations: [0, 1],
            focus: CGPoint(x: sheenBox.midX, y: sheenBox.midY),
            center: CGPoint(x: sheenBox.midX, y: sheenBox.midY),
            radius: max(sheenBox.width, sheenBox.height) / 2
        )

        let glint = CGPath(
            ellipseIn: CGRect(
                x: center.x - radius * 0.56,
                y: center.y + radius * 0.30,
                width: radius * 0.30,
                height: radius * 0.40
            ),
            transform: nil
        )
        let glintBox = glint.boundingBoxOfPath
        drawRadialGradient(
            in: context,
            clippingTo: [body, glint],
            colors: [Palette.glossBright, Palette.clear],
            locations: [0, 1],
            focus: CGPoint(x: glintBox.midX, y: glintBox.midY),
            center: CGPoint(x: glintBox.midX, y: glintBox.midY),
            radius: max(glintBox.width, glintBox.height) / 2
        )

        context.addPath(body)
        context.setStrokeColor(palette.outline)
        context.setLineWidth(max(0.5, radius * 0.035))
        context.strokePath()

        // The blackened stub of thread knotted under the fruit.
        let knot = CGPoint(x: center.x - radius * 0.10, y: center.y - radius * 0.84)
        context.setFillColor(palette.knot)
        context.addEllipse(in: CGRect(
            x: knot.x - radius * 0.21,
            y: knot.y - radius * 0.14,
            width: radius * 0.42,
            height: radius * 0.28
        ))
        context.addEllipse(in: CGRect(
            x: knot.x + radius * 0.08,
            y: knot.y - radius * 0.04,
            width: radius * 0.26,
            height: radius * 0.21
        ))
        context.fillPath()
    }

    private func drawNazar(in context: CGContext, size: CGSize) {
        let width = size.width
        let height = size.height

        drawThread(in: context, size: size, to: height * 0.86)

        let center = CGPoint(x: width * 0.5, y: height * 0.42)
        let radius = min(width, height) * 0.42

        let rings: [(CGFloat, CGColor)] = [
            (1.00, Palette.nazarOuter),
            (0.74, Palette.nazarWhite),
            (0.46, Palette.nazarMid),
            (0.20, Palette.nazarPupil)
        ]

        for (fraction, color) in rings {
            context.setFillColor(color)
            context.addEllipse(in: CGRect(
                x: center.x - radius * fraction,
                y: center.y - radius * fraction,
                width: radius * fraction * 2,
                height: radius * fraction * 2
            ))
            context.fillPath()
        }

        context.setFillColor(Palette.highlight)
        context.addEllipse(in: CGRect(
            x: center.x - radius * 0.62,
            y: center.y + radius * 0.34,
            width: radius * 0.34,
            height: radius * 0.22
        ))
        context.fillPath()
    }

    private func drawBell(in context: CGContext, size: CGSize) {
        let width = size.width
        let height = size.height

        drawThread(in: context, size: size, to: height * 0.90)

        // Suspension loop.
        context.setStrokeColor(Palette.brassDark)
        context.setLineWidth(width * 0.045)
        context.addEllipse(in: CGRect(
            x: width * 0.5 - width * 0.06,
            y: height * 0.82,
            width: width * 0.12,
            height: height * 0.08
        ))
        context.strokePath()

        let rimY = height * 0.24
        let apexY = height * 0.82
        let halfWidth = width * 0.36

        let body = CGMutablePath()
        body.move(to: CGPoint(x: width * 0.5 - halfWidth, y: rimY))
        body.addCurve(
            to: CGPoint(x: width * 0.5, y: apexY),
            control1: CGPoint(x: width * 0.5 - halfWidth * 0.95, y: rimY + (apexY - rimY) * 0.55),
            control2: CGPoint(x: width * 0.5 - halfWidth * 0.45, y: apexY)
        )
        body.addCurve(
            to: CGPoint(x: width * 0.5 + halfWidth, y: rimY),
            control1: CGPoint(x: width * 0.5 + halfWidth * 0.45, y: apexY),
            control2: CGPoint(x: width * 0.5 + halfWidth * 0.95, y: rimY + (apexY - rimY) * 0.55)
        )
        body.closeSubpath()

        context.addPath(body)
        fillWithVerticalGradient(
            context,
            top: Palette.brassLight,
            bottom: Palette.brassDark,
            in: body.boundingBoxOfPath
        )

        // Rim band.
        let band = CGRect(
            x: width * 0.5 - halfWidth,
            y: rimY - height * 0.05,
            width: halfWidth * 2,
            height: height * 0.07
        )
        context.setFillColor(Palette.brassMid)
        context.addPath(CGPath(roundedRect: band, cornerWidth: height * 0.03, cornerHeight: height * 0.03, transform: nil))
        context.fillPath()

        // Clapper.
        context.setFillColor(Palette.brassDark)
        context.addEllipse(in: CGRect(
            x: width * 0.5 - width * 0.065,
            y: band.minY - height * 0.10,
            width: width * 0.13,
            height: height * 0.11
        ))
        context.fillPath()
    }

    /// `isLit` is the alternate variant. Unlit draws only the lamp and a spent
    /// wick, so the toggle ritual reads as actually lighting it.
    private func drawDiya(in context: CGContext, size: CGSize, isLit: Bool) {
        let width = size.width
        let height = size.height

        drawThread(in: context, size: size, to: height * 0.92)

        let flameBase = CGPoint(x: width * 0.5, y: height * 0.40)

        if isLit {
            let flame = CGMutablePath()
            flame.move(to: flameBase)
            flame.addQuadCurve(
                to: CGPoint(x: width * 0.5, y: height * 0.80),
                control: CGPoint(x: width * 0.30, y: height * 0.60)
            )
            flame.addQuadCurve(
                to: flameBase,
                control: CGPoint(x: width * 0.70, y: height * 0.60)
            )
            flame.closeSubpath()

            context.addPath(flame)
            fillWithVerticalGradient(
                context,
                top: Palette.flameTop,
                bottom: Palette.flameBottom,
                in: flame.boundingBoxOfPath
            )
        } else {
            // A short blackened wick where the flame would be.
            context.setStrokeColor(Palette.spentWick)
            context.setLineWidth(width * 0.05)
            context.move(to: flameBase)
            context.addLine(to: CGPoint(x: width * 0.5, y: height * 0.48))
            context.strokePath()
        }

        // Bowl: a half-ellipse with a flat rim.
        let bowlRect = CGRect(
            x: width * 0.14,
            y: height * 0.08,
            width: width * 0.72,
            height: height * 0.30
        )
        let bowl = CGMutablePath()
        bowl.move(to: CGPoint(x: bowlRect.minX, y: bowlRect.maxY))
        bowl.addQuadCurve(
            to: CGPoint(x: bowlRect.maxX, y: bowlRect.maxY),
            control: CGPoint(x: bowlRect.midX, y: bowlRect.minY - bowlRect.height * 0.35)
        )
        bowl.closeSubpath()

        context.addPath(bowl)
        fillWithVerticalGradient(
            context,
            top: Palette.clayLight,
            bottom: Palette.clayDark,
            in: bowlRect
        )

        context.setFillColor(Palette.clayRim)
        context.addPath(CGPath(
            roundedRect: CGRect(
                x: bowlRect.minX,
                y: bowlRect.maxY - height * 0.028,
                width: bowlRect.width,
                height: height * 0.05
            ),
            cornerWidth: height * 0.02,
            cornerHeight: height * 0.02,
            transform: nil
        ))
        context.fillPath()
    }

    // MARK: - Shared drawing

    /// The short length of thread joining the rope to the charm body.
    private func drawThread(in context: CGContext, size: CGSize, to y: CGFloat) {
        context.setStrokeColor(Palette.thread)
        context.setLineWidth(max(1, size.width * 0.022))
        context.move(to: CGPoint(x: size.width * 0.5, y: size.height))
        context.addLine(to: CGPoint(x: size.width * 0.5, y: y))
        context.strokePath()
    }

    /// Draws a multi-stop linear gradient through the intersection of `paths`.
    ///
    /// Taking the clips as an argument rather than relying on the current path
    /// lets a caller confine a highlight to both the shape it belongs to *and*
    /// the body it sits on, which is how the gloss stays inside the chilli.
    private func drawLinearGradient(
        in context: CGContext,
        clippingTo paths: [CGPath],
        colors: [CGColor],
        locations: [CGFloat],
        from start: CGPoint,
        to end: CGPoint
    ) {
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: colors as CFArray,
            locations: locations
        ) else { return }

        context.saveGState()
        for path in paths {
            context.addPath(path)
            context.clip()
        }
        context.drawLinearGradient(
            gradient,
            start: start,
            end: end,
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
        context.restoreGState()
    }

    /// Draws a multi-stop radial gradient through the intersection of `paths`.
    ///
    /// `focus` is where the light appears to come from; offsetting it from
    /// `center` is what makes a circle look spherical.
    private func drawRadialGradient(
        in context: CGContext,
        clippingTo paths: [CGPath],
        colors: [CGColor],
        locations: [CGFloat],
        focus: CGPoint,
        center: CGPoint,
        radius: CGFloat
    ) {
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: colors as CFArray,
            locations: locations
        ) else { return }

        context.saveGState()
        for path in paths {
            context.addPath(path)
            context.clip()
        }
        context.drawRadialGradient(
            gradient,
            startCenter: focus,
            startRadius: 0,
            endCenter: center,
            endRadius: radius,
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
        context.restoreGState()
    }

    /// Fills the context's current path with a vertical two-stop gradient.
    /// Clips rather than using `drawLinearGradient` directly on the path so the
    /// call site can keep composing paths naturally.
    private func fillWithVerticalGradient(
        _ context: CGContext,
        top: CGColor,
        bottom: CGColor,
        in rect: CGRect
    ) {
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: [bottom, top] as CFArray,
            locations: [0, 1]
        ) else {
            context.setFillColor(top)
            context.fillPath()
            return
        }

        context.saveGState()
        context.clip()
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.midX, y: rect.minY),
            end: CGPoint(x: rect.midX, y: rect.maxY),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
        context.restoreGState()
    }

    /// Shading ramp for a chilli, dark underside through to lit crest.
    private struct ChilliPalette {
        let light: CGColor
        let mid: CGColor
        let dark: CGColor
        let shadowEdge: CGColor
        let outline: CGColor
        let stem: CGColor

        static let fresh = ChilliPalette(
            light: Palette.color(132, 204, 96),
            mid: Palette.color(58, 150, 66),
            dark: Palette.color(26, 104, 48),
            shadowEdge: Palette.color(16, 74, 38),
            outline: Palette.color(11, 54, 28),
            stem: Palette.color(52, 40, 22)
        )

        static let dried = ChilliPalette(
            light: Palette.color(108, 162, 84),
            mid: Palette.color(54, 118, 60),
            dark: Palette.color(30, 84, 44),
            shadowEdge: Palette.color(20, 60, 34),
            outline: Palette.color(14, 44, 26),
            stem: Palette.color(58, 46, 28)
        )
    }

    /// Shading ramp for the lemon, plus the two secondary lights that keep the
    /// shaded side from going flat.
    private struct LemonPalette {
        let specular: CGColor
        let light: CGColor
        let mid: CGColor
        let dark: CGColor
        let shadowEdge: CGColor
        let rimLight: CGColor
        let occlusion: CGColor
        let outline: CGColor
        let knot: CGColor

        static let fresh = LemonPalette(
            specular: Palette.color(255, 252, 218),
            light: Palette.color(255, 234, 92),
            mid: Palette.color(250, 205, 26),
            dark: Palette.color(212, 158, 12),
            shadowEdge: Palette.color(168, 118, 10),
            rimLight: Palette.color(255, 214, 96, 0.55),
            occlusion: Palette.color(96, 62, 8, 0.42),
            outline: Palette.color(132, 92, 8),
            knot: Palette.color(58, 56, 58)
        )

        static let dried = LemonPalette(
            specular: Palette.color(248, 244, 206),
            light: Palette.color(236, 216, 100),
            mid: Palette.color(220, 188, 50),
            dark: Palette.color(180, 144, 28),
            shadowEdge: Palette.color(142, 110, 20),
            rimLight: Palette.color(236, 198, 90, 0.45),
            occlusion: Palette.color(82, 56, 10, 0.44),
            outline: Palette.color(112, 84, 16),
            knot: Palette.color(54, 52, 54)
        )
    }

    fileprivate enum Palette {
        static func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
            CGColor(srgbRed: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
        }

        static let thread = color(120, 108, 96)
        static let highlight = color(255, 255, 255, 0.55)

        /// Fully transparent white, for gradients that fade out. Matching the
        /// RGB of whatever it fades from avoids a grey fringe.
        static let clear = color(255, 255, 255, 0)
        static let glossSoft = color(255, 255, 255, 0.34)
        static let glossBright = color(255, 255, 255, 0.72)
        static let contactShadow = color(24, 34, 22, 0.42)

        /// The same colour at zero alpha, so a gradient fades to nothing
        /// rather than toward white.
        static func fading(_ color: CGColor) -> CGColor {
            color.copy(alpha: 0) ?? clear
        }

        static let nazarOuter = color(23, 66, 138)
        static let nazarWhite = color(244, 246, 250)
        static let nazarMid = color(46, 134, 193)
        static let nazarPupil = color(18, 24, 38)

        static let brassLight = color(226, 190, 92)
        static let brassMid = color(198, 158, 62)
        static let brassDark = color(140, 106, 34)

        static let flameTop = color(255, 214, 110)
        static let flameBottom = color(232, 122, 38)
        static let spentWick = color(58, 48, 44)

        static let clayLight = color(190, 108, 66)
        static let clayDark = color(134, 66, 40)
        static let clayRim = color(158, 84, 50)
    }
}
