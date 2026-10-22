import AppKit
import CoreText

// A simple vector wordmark, rendered at the App Store icon size.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
CTFontManagerRegisterFontsForURL(root.appendingPathComponent("FitOut/Resources/Fonts/orbitron-800.ttf") as CFURL, .process, nil)
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
NSColor(calibratedWhite: 0.025, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1024, height: 1024)).fill()
let attributes: [NSAttributedString.Key: Any] = [.font: NSFont(name: "Orbitron-ExtraBold", size: 390)!, .foregroundColor: NSColor(red: 1, green: 0.27, blue: 0.015, alpha: 1)]
let wordmark = NSAttributedString(string: "F", attributes: attributes)
let size = wordmark.size()
wordmark.draw(at: NSPoint(x: (1024 - size.width) / 2, y: (1024 - size.height) / 2 + 25))
NSGraphicsContext.restoreGraphicsState()
let destination = root.appendingPathComponent("FitOut/Resources/Assets.xcassets/AppIcon.appiconset")
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
try bitmap.representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent("AppIcon.png"))
try """
{"images":[{"filename":"AppIcon.png","idiom":"universal","platform":"ios","size":"1024x1024"}],"info":{"author":"xcode","version":1}}
""".write(to: destination.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
