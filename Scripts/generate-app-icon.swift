import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Draws the CharmDrop app icon at every size Apple's icns container needs,
/// then asks `iconutil` to assemble `Resources/AppIcon.icns`.
///
/// The mark is the hanging Nimbu Mirchi totem on a full-bleed tile so macOS
/// can apply its own squircle mask. Small sizes drop the chilli stack and keep
/// the lemon, which is the only shape that still reads at 16px.

let repoRoot: URL = {
    if CommandLine.arguments.count > 1 {
        return URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
    }
    let script = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
    let folder = script.deletingLastPathComponent()
    if folder.lastPathComponent == "Scripts" {
        return folder.deletingLastPathComponent()
    }
    return folder
}()
let resources = repoRoot.appendingPathComponent("Resources", isDirectory: true)
let iconset = resources.appendingPathComponent("AppIcon.iconset", isDirectory: true)
let icns = resources.appendingPathComponent("AppIcon.icns")

try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

struct Slot {
    let name: String
    let pixels: Int
}

let slots: [Slot] = [
    Slot(name: "icon_16x16.png", pixels: 16),
    Slot(name: "icon_16x16@2x.png", pixels: 32),
    Slot(name: "icon_32x32.png", pixels: 32),
    Slot(name: "icon_32x32@2x.png", pixels: 64),
    Slot(name: "icon_128x128.png", pixels: 128),
    Slot(name: "icon_128x128@2x.png", pixels: 256),
    Slot(name: "icon_256x256.png", pixels: 256),
    Slot(name: "icon_256x256@2x.png", pixels: 512),
    Slot(name: "icon_512x512.png", pixels: 512),
    Slot(name: "icon_512x512@2x.png", pixels: 1024)
]

for slot in slots {
    guard let image = AppIconArtwork.image(pixels: slot.pixels) else {
        fputs("failed to draw \(slot.name)\n", stderr)
        exit(1)
    }
    let url = iconset.appendingPathComponent(slot.name)
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        fputs("failed to write \(slot.name)\n", stderr)
        exit(1)
    }
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
}

let preview = resources.appendingPathComponent("AppIcon-1024.png")
if let image = AppIconArtwork.image(pixels: 1024),
   let destination = CGImageDestinationCreateWithURL(
        preview as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
   ) {
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", "-o", icns.path, iconset.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    fputs("iconutil failed with status \(iconutil.terminationStatus)\n", stderr)
    exit(1)
}

try? FileManager.default.removeItem(at: iconset)
print("Wrote \(icns.path)")

// MARK: - Artwork

enum AppIconArtwork {

    static func image(pixels: Int) -> CGImage? {
        let size = CGFloat(pixels)
        guard let context = CGContext(
            data: nil,
            width: pixels,
            height: pixels,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.setShouldAntialias(true)
        context.setAllowsAntialiasing(true)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        drawBackground(in: context, size: size)
        drawCharm(in: context, size: size, compact: pixels <= 64)
        return context.makeImage()
    }

    private static func drawBackground(in context: CGContext, size: CGFloat) {
        let bounds = CGRect(x: 0, y: 0, width: size, height: size)
        context.saveGState()
        context.addRect(bounds)
        context.clip()

        drawRadial(
            in: context,
            colors: [color(42, 118, 64), color(14, 58, 40), color(8, 32, 24)],
            locations: [0, 0.55, 1],
            focus: CGPoint(x: size * 0.32, y: size * 0.78),
            center: CGPoint(x: size * 0.5, y: size * 0.42),
            radius: size * 1.15
        )

        // Warm key light in the upper-left, like a physical tile.
        drawRadial(
            in: context,
            colors: [color(255, 214, 120, 0.28), color(255, 214, 120, 0)],
            locations: [0, 1],
            focus: CGPoint(x: size * 0.28, y: size * 0.82),
            center: CGPoint(x: size * 0.28, y: size * 0.82),
            radius: size * 0.62
        )

        context.restoreGState()
    }

    private static func drawCharm(in context: CGContext, size: CGFloat, compact: Bool) {
        let ropeColor = color(214, 186, 120)
        let ropeWidth = max(1.2, size * 0.028)

        context.setStrokeColor(ropeColor)
        context.setLineWidth(ropeWidth)
        context.move(to: CGPoint(x: size * 0.5, y: size))
        context.addLine(to: CGPoint(x: size * 0.5, y: size * (compact ? 0.62 : 0.84)))
        context.strokePath()

        if compact {
            drawLemon(
                in: context,
                center: CGPoint(x: size * 0.5, y: size * 0.42),
                radius: size * 0.28
            )
            // Two simple chillies so 16–32px still reads as the totem, not
            // just a yellow circle.
            drawSimpleChilli(
                in: context,
                origin: CGPoint(x: size * 0.50, y: size * 0.62),
                tip: CGPoint(x: size * 0.18, y: size * 0.70),
                thickness: size * 0.11
            )
            drawSimpleChilli(
                in: context,
                origin: CGPoint(x: size * 0.50, y: size * 0.58),
                tip: CGPoint(x: size * 0.84, y: size * 0.68),
                thickness: size * 0.11
            )
            return
        }

        let stack: [(y: CGFloat, right: Bool, length: CGFloat, thickness: CGFloat, tilt: CGFloat)] = [
            (0.80, true, 0.46, 0.085, 0.10),
            (0.735, false, 0.54, 0.092, 0.06),
            (0.67, true, 0.58, 0.096, 0.08),
            (0.605, false, 0.54, 0.090, 0.05),
            (0.545, true, 0.46, 0.082, 0.09)
        ]

        for (index, chilli) in stack.enumerated() {
            let recession = 1 - CGFloat(index) / CGFloat(stack.count - 1)
            drawChilli(
                in: context,
                center: CGPoint(x: size * 0.5, y: size * chilli.y),
                length: size * chilli.length,
                thickness: size * chilli.thickness,
                tilt: chilli.tilt,
                pointsRight: chilli.right,
                recession: recession
            )
        }

        drawLemon(
            in: context,
            center: CGPoint(x: size * 0.5, y: size * 0.30),
            radius: size * 0.22
        )
    }

    private static func drawSimpleChilli(
        in context: CGContext,
        origin: CGPoint,
        tip: CGPoint,
        thickness: CGFloat
    ) {
        let direction = CGPoint(x: tip.x - origin.x, y: tip.y - origin.y)
        let length = hypot(direction.x, direction.y)
        guard length > 0 else { return }
        let nx = -direction.y / length
        let ny = direction.x / length
        let belly = CGPoint(x: origin.x + direction.x * 0.45, y: origin.y + direction.y * 0.45)

        let path = CGMutablePath()
        path.move(to: origin)
        path.addQuadCurve(
            to: tip,
            control: CGPoint(x: belly.x + nx * thickness, y: belly.y + ny * thickness)
        )
        path.addQuadCurve(
            to: origin,
            control: CGPoint(x: belly.x - nx * thickness, y: belly.y - ny * thickness)
        )
        path.closeSubpath()

        context.addPath(path)
        fillLinear(
            in: context,
            colors: [color(28, 92, 46), color(86, 176, 78)],
            from: CGPoint(x: origin.x, y: origin.y - thickness),
            to: CGPoint(x: origin.x, y: origin.y + thickness)
        )
    }

    private static func drawChilli(
        in context: CGContext,
        center: CGPoint,
        length: CGFloat,
        thickness: CGFloat,
        tilt: CGFloat,
        pointsRight: Bool,
        recession: CGFloat
    ) {
        context.saveGState()
        defer { context.restoreGState() }

        context.translateBy(x: center.x, y: center.y)
        context.rotate(by: pointsRight ? tilt : -tilt)
        if !pointsRight { context.scaleBy(x: -1, y: 1) }

        let halfLength = length / 2
        let halfThickness = thickness / 2
        let baseX = -halfLength
        let tip = CGPoint(x: halfLength, y: thickness * 0.18)
        let belly = baseX + length * 0.32
        let shoulder = baseX + length * 0.68

        let body = CGMutablePath()
        body.move(to: CGPoint(x: baseX, y: 0))
        body.addCurve(
            to: CGPoint(x: belly, y: halfThickness),
            control1: CGPoint(x: baseX + length * 0.02, y: halfThickness),
            control2: CGPoint(x: baseX + length * 0.18, y: halfThickness)
        )
        body.addCurve(
            to: tip,
            control1: CGPoint(x: shoulder, y: halfThickness * 0.78),
            control2: CGPoint(x: baseX + length * 0.94, y: halfThickness * 0.28)
        )
        body.addCurve(
            to: CGPoint(x: belly, y: -halfThickness),
            control1: CGPoint(x: baseX + length * 0.94, y: -halfThickness * 0.28),
            control2: CGPoint(x: shoulder, y: -halfThickness * 0.78)
        )
        body.addCurve(
            to: CGPoint(x: baseX, y: 0),
            control1: CGPoint(x: baseX + length * 0.18, y: -halfThickness),
            control2: CGPoint(x: baseX + length * 0.02, y: -halfThickness)
        )
        body.closeSubpath()

        context.setStrokeColor(color(48, 34, 18))
        context.setLineWidth(max(0.6, thickness * 0.18))
        context.move(to: CGPoint(x: baseX + thickness * 0.15, y: 0))
        context.addQuadCurve(
            to: CGPoint(x: baseX - length * 0.08, y: thickness * 0.55),
            control: CGPoint(x: baseX - length * 0.07, y: 0)
        )
        context.strokePath()

        context.saveGState()
        context.setShadow(
            offset: CGSize(width: thickness * 0.08, height: -thickness * 0.18),
            blur: thickness * 0.35,
            color: color(8, 18, 10, 0.45)
        )
        context.addPath(body)
        context.setFillColor(color(46, 122, 58))
        context.fillPath()
        context.restoreGState()

        fillLinear(
            in: context,
            clippingTo: body,
            colors: [color(16, 70, 36), color(36, 112, 52), color(86, 176, 78), color(150, 214, 110)],
            from: CGPoint(x: 0, y: -halfThickness),
            to: CGPoint(x: 0, y: halfThickness)
        )

        if recession > 0 {
            context.saveGState()
            context.addPath(body)
            context.clip()
            context.setFillColor(color(16, 70, 36, recession * 0.22))
            context.fill(body.boundingBoxOfPath)
            context.restoreGState()
        }

        context.addPath(body)
        context.setStrokeColor(color(10, 48, 26))
        context.setLineWidth(max(0.5, thickness * 0.08))
        context.strokePath()
    }

    private static func drawLemon(in context: CGContext, center: CGPoint, radius: CGFloat) {
        let bounds = CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        )
        let body = CGPath(ellipseIn: bounds, transform: nil)

        context.saveGState()
        context.setShadow(
            offset: CGSize(width: 0, height: -radius * 0.12),
            blur: radius * 0.35,
            color: color(6, 16, 10, 0.5)
        )
        context.addPath(body)
        context.setFillColor(color(250, 205, 26))
        context.fillPath()
        context.restoreGState()

        drawRadial(
            in: context,
            clippingTo: body,
            colors: [
                color(255, 252, 218),
                color(255, 234, 92),
                color(250, 205, 26),
                color(212, 158, 12),
                color(168, 118, 10)
            ],
            locations: [0, 0.26, 0.60, 0.87, 1],
            focus: CGPoint(x: center.x - radius * 0.36, y: center.y + radius * 0.34),
            center: center,
            radius: radius * 1.44
        )

        drawRadial(
            in: context,
            clippingTo: body,
            colors: [color(255, 255, 255, 0.7), color(255, 255, 255, 0)],
            locations: [0, 1],
            focus: CGPoint(x: center.x - radius * 0.38, y: center.y + radius * 0.38),
            center: CGPoint(x: center.x - radius * 0.38, y: center.y + radius * 0.38),
            radius: radius * 0.42
        )

        context.addPath(body)
        context.setStrokeColor(color(132, 92, 8))
        context.setLineWidth(max(0.5, radius * 0.04))
        context.strokePath()
    }

    private static func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
    }

    private static func drawRadial(
        in context: CGContext,
        clippingTo path: CGPath? = nil,
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
        if let path {
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

    private static func fillLinear(
        in context: CGContext,
        clippingTo path: CGPath? = nil,
        colors: [CGColor],
        from start: CGPoint,
        to end: CGPoint
    ) {
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: colors as CFArray,
            locations: nil
        ) else {
            context.setFillColor(colors.last ?? color(0, 0, 0))
            context.fillPath()
            return
        }

        context.saveGState()
        if let path {
            context.addPath(path)
            context.clip()
        } else {
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
}
