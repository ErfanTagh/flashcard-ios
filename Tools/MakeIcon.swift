import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Redraws public/recallcards-icon.svg at app-icon size. The SVG insets its
// rounded square inside the canvas; an iOS icon is full-bleed and masked by the
// system, so the gradient fills the whole square and the book keeps the same
// position *relative to that square* as in the original.
let size = 1024.0
let space = CGColorSpace(name: CGColorSpace.sRGB)!

guard let ctx = CGContext(data: nil, width: Int(size), height: Int(size),
                          bitsPerComponent: 8, bytesPerRow: 0, space: space,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("no context")
}

// Flip to SVG-style top-left origin.
ctx.translateBy(x: 0, y: size)
ctx.scaleBy(x: 1, y: -1)

let violet = CGColor(colorSpace: space, components: [139/255, 92/255, 246/255, 1])!  // #8B5CF6
let pink   = CGColor(colorSpace: space, components: [236/255, 72/255, 153/255, 1])!  // #EC4899
let gradient = CGGradient(colorsSpace: space, colors: [violet, pink] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: size, y: size), options: [])

// The SVG rect occupies 10…110 of a 120 box, with the book at 40…80 x, 25…85 y —
// which sits slightly high. Shifted down 5 units so it is centred in the square.
func p(_ x: Double, _ y: Double) -> CGPoint {
    CGPoint(x: (x - 10) / 100 * size, y: (y - 5) / 100 * size)
}

ctx.setStrokeColor(CGColor(colorSpace: space, components: [1, 1, 1, 1])!)
ctx.setLineWidth(3.0 / 100 * size)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)

// Left page.
ctx.move(to: p(40, 35))
ctx.addLine(to: p(40, 85))
ctx.addLine(to: p(60, 75))
ctx.addLine(to: p(60, 25))
ctx.closePath()
ctx.strokePath()

// Right page.
ctx.move(to: p(60, 25))
ctx.addLine(to: p(60, 75))
ctx.addLine(to: p(80, 85))
ctx.addLine(to: p(80, 35))
ctx.closePath()
ctx.strokePath()

// Spine rule across the top.
ctx.move(to: p(40, 35))
ctx.addLine(to: p(80, 35))
ctx.strokePath()

guard let image = ctx.makeImage() else { fatalError("no image") }
let out = URL(fileURLWithPath: CommandLine.arguments[1])
guard let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fatalError("no destination")
}
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("wrote \(out.path)")
