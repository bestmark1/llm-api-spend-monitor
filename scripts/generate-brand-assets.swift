#!/usr/bin/env swift

import AppKit
import CoreGraphics
import Foundation

private let designSize: CGFloat = 1024
private let outputURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("LLMSpendMonitor/Resources/Spender.icns")
private let iconsetURL = FileManager.default.temporaryDirectory
    .appendingPathComponent("Spender-\(UUID().uuidString).iconset", isDirectory: true)

private struct GradientStop {
    let color: CGColor
    let location: CGFloat
}

private func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

private func appShape() -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 262, y: 64))
    path.addCurve(
        to: CGPoint(x: 64, y: 262),
        control1: CGPoint(x: 139, y: 64),
        control2: CGPoint(x: 64, y: 139)
    )
    path.addLine(to: CGPoint(x: 64, y: 762))
    path.addCurve(
        to: CGPoint(x: 262, y: 960),
        control1: CGPoint(x: 64, y: 885),
        control2: CGPoint(x: 139, y: 960)
    )
    path.addLine(to: CGPoint(x: 762, y: 960))
    path.addCurve(
        to: CGPoint(x: 960, y: 762),
        control1: CGPoint(x: 885, y: 960),
        control2: CGPoint(x: 960, y: 885)
    )
    path.addLine(to: CGPoint(x: 960, y: 262))
    path.addCurve(
        to: CGPoint(x: 762, y: 64),
        control1: CGPoint(x: 960, y: 139),
        control2: CGPoint(x: 885, y: 64)
    )
    path.closeSubpath()
    return path
}

private func pocketPath(compact: Bool) -> CGPath {
    let sideY: CGFloat = compact ? 492 : 500
    let centerY: CGFloat = compact ? 556 : 554
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 64, y: sideY))
    path.addCurve(
        to: CGPoint(x: 332, y: centerY),
        control1: CGPoint(x: 145, y: compact ? 441 : 451),
        control2: CGPoint(x: 235, y: compact ? 535 : 535)
    )
    path.addCurve(
        to: CGPoint(x: 692, y: centerY),
        control1: CGPoint(x: 436, y: compact ? 579 : 574),
        control2: CGPoint(x: 588, y: compact ? 579 : 574)
    )
    path.addCurve(
        to: CGPoint(x: 960, y: sideY),
        control1: CGPoint(x: 789, y: compact ? 535 : 535),
        control2: CGPoint(x: 879, y: compact ? 441 : 451)
    )
    path.addLine(to: CGPoint(x: 960, y: 762))
    path.addCurve(
        to: CGPoint(x: 762, y: 960),
        control1: CGPoint(x: 960, y: 885),
        control2: CGPoint(x: 885, y: 960)
    )
    path.addLine(to: CGPoint(x: 262, y: 960))
    path.addCurve(
        to: CGPoint(x: 64, y: 762),
        control1: CGPoint(x: 139, y: 960),
        control2: CGPoint(x: 64, y: 885)
    )
    path.closeSubpath()
    return path
}

private func pocketEdge(compact: Bool) -> CGPath {
    let sideY: CGFloat = compact ? 492 : 500
    let centerY: CGFloat = compact ? 556 : 554
    let path = CGMutablePath()
    path.move(to: CGPoint(x: 64, y: sideY))
    path.addCurve(
        to: CGPoint(x: 332, y: centerY),
        control1: CGPoint(x: 145, y: compact ? 441 : 451),
        control2: CGPoint(x: 235, y: 535)
    )
    path.addCurve(
        to: CGPoint(x: 692, y: centerY),
        control1: CGPoint(x: 436, y: compact ? 579 : 574),
        control2: CGPoint(x: 588, y: compact ? 579 : 574)
    )
    path.addCurve(
        to: CGPoint(x: 960, y: sideY),
        control1: CGPoint(x: 789, y: 535),
        control2: CGPoint(x: 879, y: compact ? 441 : 451)
    )
    return path
}

private func drawLinearGradient(
    in context: CGContext,
    path: CGPath,
    stops: [GradientStop],
    start: CGPoint,
    end: CGPoint
) {
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: stops.map(\.color) as CFArray,
        locations: stops.map(\.location)
    )!
    context.saveGState()
    context.addPath(path)
    context.clip()
    context.drawLinearGradient(
        gradient,
        start: start,
        end: end,
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )
    context.restoreGState()
}

private func drawRadialAccent(in context: CGContext, clippingPath: CGPath) {
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [color(0x9B64C8, alpha: 0.28), color(0x7954B4, alpha: 0.12), color(0x59449B, alpha: 0)] as CFArray,
        locations: [0, 0.5, 1]
    )!
    context.saveGState()
    context.addPath(clippingPath)
    context.clip()
    context.drawRadialGradient(
        gradient,
        startCenter: CGPoint(x: 890, y: 860),
        startRadius: 0,
        endCenter: CGPoint(x: 890, y: 860),
        endRadius: 150,
        options: []
    )
    context.restoreGState()
}

private func drawAI(in context: CGContext) {
    let mark = CGMutablePath()
    mark.move(to: CGPoint(x: 468, y: 514))
    mark.addLine(to: CGPoint(x: 491, y: 440))
    mark.addLine(to: CGPoint(x: 507, y: 440))
    mark.addLine(to: CGPoint(x: 531, y: 514))
    mark.addLine(to: CGPoint(x: 513, y: 514))
    mark.addLine(to: CGPoint(x: 507, y: 494))
    mark.addLine(to: CGPoint(x: 491, y: 494))
    mark.addLine(to: CGPoint(x: 485, y: 514))
    mark.closeSubpath()
    mark.move(to: CGPoint(x: 496, y: 466))
    mark.addLine(to: CGPoint(x: 491, y: 481))
    mark.addLine(to: CGPoint(x: 503, y: 481))
    mark.closeSubpath()

    context.saveGState()
    context.translateBy(x: 512, y: 477)
    context.scaleBy(x: 0.82, y: 0.82)
    context.translateBy(x: -512, y: -477)
    context.addPath(mark)
    context.setFillColor(color(0x102E68))
    context.drawPath(using: .eoFill)
    context.setFillColor(color(0x102E68))
    context.fill(CGRect(x: 543, y: 440, width: 14, height: 74))
    context.restoreGState()
}

private func renderIcon(pixelSize: Int, compact: Bool) throws -> Data {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let graphicsContext = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw CocoaError(.fileWriteUnknown)
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = graphicsContext
    let context = graphicsContext.cgContext
    context.clear(CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize))
    let scale = CGFloat(pixelSize) / designSize
    context.translateBy(x: 0, y: CGFloat(pixelSize))
    context.scaleBy(x: scale, y: -scale)

    let shape = appShape()
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: 8), blur: 24, color: color(0x07132E, alpha: 0.08))
    context.addPath(shape)
    context.setFillColor(color(0x2453B8))
    context.fillPath()
    context.restoreGState()

    drawLinearGradient(
        in: context,
        path: shape,
        stops: [
            GradientStop(color: color(0x4777DE), location: 0),
            GradientStop(color: color(0x2453B8), location: 0.48),
            GradientStop(color: color(0x173577), location: 0.82),
            GradientStop(color: color(0x34347D), location: 1),
        ],
        start: CGPoint(x: 180, y: 110),
        end: CGPoint(x: 830, y: 920)
    )

    let cardRect = compact
        ? CGRect(x: 292, y: 342, width: 440, height: 242)
        : CGRect(x: 306, y: 350, width: 412, height: 218)
    let card = CGPath(roundedRect: cardRect, cornerWidth: compact ? 32 : 30, cornerHeight: compact ? 32 : 30, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: 6), blur: compact ? 0 : 9, color: color(0x07132E, alpha: 0.18))
    drawLinearGradient(
        in: context,
        path: card,
        stops: [
            GradientStop(color: color(0xF5F6F8), location: 0),
            GradientStop(color: color(0xD8DCE2), location: 0.56),
            GradientStop(color: color(0xB9C0CA), location: 1),
        ],
        start: CGPoint(x: 512, y: cardRect.minY),
        end: CGPoint(x: 512, y: cardRect.maxY)
    )
    context.restoreGState()
    context.addPath(card)
    context.setStrokeColor(color(0x929BA9))
    context.setLineWidth(compact ? 10 : 4)
    context.strokePath()

    if !compact {
        drawAI(in: context)
    }

    let pocket = pocketPath(compact: compact)
    drawLinearGradient(
        in: context,
        path: pocket,
        stops: [
            GradientStop(color: color(0x3F70DA), location: 0),
            GradientStop(color: color(0x214CA9), location: 0.55),
            GradientStop(color: color(0x183577), location: 0.87),
            GradientStop(color: color(0x3A347D), location: 1),
        ],
        start: CGPoint(x: 175, y: 500),
        end: CGPoint(x: 835, y: 910)
    )
    if !compact {
        drawRadialAccent(in: context, clippingPath: pocket)
    }
    context.addPath(pocketEdge(compact: compact))
    context.setStrokeColor(color(compact ? 0x183B82 : 0x264B9D, alpha: 0.92))
    context.setLineWidth(compact ? 18 : 7)
    context.strokePath()

    NSGraphicsContext.restoreGraphicsState()
    guard let data = bitmap.representation(using: .png, properties: [.compressionFactor: 1]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    return data
}

private func writeIcon(_ filename: String, size: Int, compact: Bool) throws {
    let data = try renderIcon(pixelSize: size, compact: compact)
    try data.write(to: iconsetURL.appendingPathComponent(filename), options: .atomic)
}

try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: iconsetURL) }

try writeIcon("icon_16x16.png", size: 16, compact: true)
try writeIcon("icon_16x16@2x.png", size: 32, compact: true)
try writeIcon("icon_32x32.png", size: 32, compact: true)
try writeIcon("icon_32x32@2x.png", size: 64, compact: false)
try writeIcon("icon_128x128.png", size: 128, compact: false)
try writeIcon("icon_128x128@2x.png", size: 256, compact: false)
try writeIcon("icon_256x256.png", size: 256, compact: false)
try writeIcon("icon_256x256@2x.png", size: 512, compact: false)
try writeIcon("icon_512x512.png", size: 512, compact: false)
try writeIcon("icon_512x512@2x.png", size: 1024, compact: false)

try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["--convert", "icns", "--output", outputURL.path, iconsetURL.path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else {
    throw CocoaError(.fileWriteUnknown)
}

print("Generated \(outputURL.path)")
