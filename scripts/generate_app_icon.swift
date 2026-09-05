#!/usr/bin/env swift
// Original Camping Buddy icon. Rebuild with: swift scripts/generate_app_icon.swift
// AppKit draws the vector geometry; no external art, fonts, or network access.
import AppKit

let output = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("App/Assets.xcassets/AppIcon.appiconset/AppIcon.png")

func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: 1)
}

let size = 1024
guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
      let graphics = CGContext(data: nil, width: size, height: size,
                               bitsPerComponent: 8, bytesPerRow: size * 4,
                               space: colorSpace,
                               bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
    fatalError("Could not create the icon drawing context")
}
let context = NSGraphicsContext(cgContext: graphics, flipped: false)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.imageInterpolation = .high
context.shouldAntialias = true

// Opaque square: iOS supplies its own corner mask.
let pine = color(0x183F35)
let canvas = NSRect(x: 0, y: 0, width: size, height: size)
pine.setFill()
canvas.fill()

// Coordinates below use the familiar top-left origin.
let flip = AffineTransform(translationByX: 0, byY: CGFloat(size))
var transform = flip
transform.scale(x: 1, y: -1)
(transform as NSAffineTransform).concat()

color(0xD9AD65).setFill()
NSBezierPath(ovalIn: NSRect(x: 687, y: 249, width: 104, height: 104)).fill()

// A single pitched shelter: warm canvas face and a quieter shaded side.
let tent = NSBezierPath()
tent.move(to: NSPoint(x: 211, y: 713))
tent.line(to: NSPoint(x: 494, y: 303))
tent.curve(to: NSPoint(x: 514, y: 303),
           controlPoint1: NSPoint(x: 500, y: 294),
           controlPoint2: NSPoint(x: 508, y: 294))
tent.line(to: NSPoint(x: 813, y: 713))
tent.curve(to: NSPoint(x: 799, y: 738),
           controlPoint1: NSPoint(x: 822, y: 726),
           controlPoint2: NSPoint(x: 815, y: 738))
tent.line(to: NSPoint(x: 225, y: 738))
tent.curve(to: NSPoint(x: 211, y: 713),
           controlPoint1: NSPoint(x: 209, y: 738),
           controlPoint2: NSPoint(x: 202, y: 726))
tent.close()
color(0xF3EDD9).setFill()
tent.fill()

NSGraphicsContext.saveGraphicsState()
tent.addClip()
let side = NSBezierPath()
side.move(to: NSPoint(x: 504, y: 296))
side.line(to: NSPoint(x: 829, y: 748))
side.line(to: NSPoint(x: 639, y: 748))
side.line(to: NSPoint(x: 504, y: 478))
side.close()
color(0xD9DDC7).setFill()
side.fill()
NSGraphicsContext.restoreGraphicsState()

// Negative-space doorway remains legible at home-screen and Settings sizes.
let doorway = NSBezierPath()
doorway.move(to: NSPoint(x: 376, y: 739))
doorway.line(to: NSPoint(x: 496, y: 488))
doorway.curve(to: NSPoint(x: 512, y: 488),
              controlPoint1: NSPoint(x: 500, y: 480),
              controlPoint2: NSPoint(x: 508, y: 480))
doorway.line(to: NSPoint(x: 640, y: 739))
doorway.close()
pine.setFill()
doorway.fill()

NSGraphicsContext.restoreGraphicsState()
guard let image = graphics.makeImage(),
      let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
    fatalError("Could not encode icon PNG")
}
try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
try png.write(to: output, options: .atomic)
print("Wrote original opaque 1024×1024 Camping Buddy icon to \(output.path)")
