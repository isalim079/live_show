import Foundation
import AppKit

func generateAppIcon() {
    let size = NSSize(width: 1024, height: 1024)
    let image = NSImage(size: size)

    image.lockFocus()
    guard let context = NSGraphicsContext.current?.cgContext else { return }

    let colorSpace = CGColorSpaceCreateDeviceRGB()

    // 1. Squircle container base
    let rect = CGRect(x: 80, y: 80, width: 864, height: 864)
    let squirclePath = CGPath(roundedRect: rect, cornerWidth: 200, cornerHeight: 200, transform: nil)

    context.saveGState()
    context.addPath(squirclePath)
    context.clip()

    // Background Gradient: Deep Midnight Indigo to Vibrant Purple
    let bgColors = [
        CGColor(red: 0.08, green: 0.07, blue: 0.18, alpha: 1.0),
        CGColor(red: 0.18, green: 0.12, blue: 0.38, alpha: 1.0),
        CGColor(red: 0.32, green: 0.14, blue: 0.52, alpha: 1.0)
    ] as CFArray

    if let bgGradient = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0.0, 0.5, 1.0]) {
        context.drawLinearGradient(bgGradient, start: CGPoint(x: 512, y: 944), end: CGPoint(x: 512, y: 80), options: [])
    }

    // Glowing Neon Horizon / Sun
    let sunCenter = CGPoint(x: 512, y: 520)
    let sunColors = [
        CGColor(red: 1.0, green: 0.45, blue: 0.25, alpha: 0.9),
        CGColor(red: 0.95, green: 0.2, blue: 0.55, alpha: 0.7),
        CGColor(red: 0.5, green: 0.1, blue: 0.6, alpha: 0.0)
    ] as CFArray
    if let sunGradient = CGGradient(colorsSpace: colorSpace, colors: sunColors, locations: [0.0, 0.45, 1.0]) {
        context.drawRadialGradient(sunGradient, startCenter: sunCenter, startRadius: 0, endCenter: sunCenter, endRadius: 360, options: [])
    }

    // Stylized Waves / Mountains
    let wave1 = CGMutablePath()
    wave1.move(to: CGPoint(x: 80, y: 340))
    wave1.addCurve(to: CGPoint(x: 512, y: 400), control1: CGPoint(x: 240, y: 460), control2: CGPoint(x: 360, y: 430))
    wave1.addCurve(to: CGPoint(x: 944, y: 320), control1: CGPoint(x: 680, y: 370), control2: CGPoint(x: 800, y: 420))
    wave1.addLine(to: CGPoint(x: 944, y: 80))
    wave1.addLine(to: CGPoint(x: 80, y: 80))
    wave1.closeSubpath()

    context.addPath(wave1)
    context.setFillColor(CGColor(red: 0.15, green: 0.08, blue: 0.35, alpha: 0.85))
    context.fillPath()

    let wave2 = CGMutablePath()
    wave2.move(to: CGPoint(x: 80, y: 220))
    wave2.addCurve(to: CGPoint(x: 512, y: 260), control1: CGPoint(x: 280, y: 290), control2: CGPoint(x: 380, y: 240))
    wave2.addCurve(to: CGPoint(x: 944, y: 200), control1: CGPoint(x: 650, y: 280), control2: CGPoint(x: 780, y: 270))
    wave2.addLine(to: CGPoint(x: 944, y: 80))
    wave2.addLine(to: CGPoint(x: 80, y: 80))
    wave2.closeSubpath()

    context.addPath(wave2)
    context.setFillColor(CGColor(red: 0.09, green: 0.05, blue: 0.22, alpha: 0.95))
    context.fillPath()

    // Sleek Desktop Display Frame Outline
    let screenRect = CGRect(x: 256, y: 340, width: 512, height: 320)
    let screenPath = CGPath(roundedRect: screenRect, cornerWidth: 28, cornerHeight: 28, transform: nil)
    context.addPath(screenPath)
    context.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.85))
    context.setLineWidth(16)
    context.strokePath()

    // Screen Stand
    let standPath = CGMutablePath()
    standPath.move(to: CGPoint(x: 480, y: 340))
    standPath.addLine(to: CGPoint(x: 470, y: 280))
    standPath.addLine(to: CGPoint(x: 430, y: 280))
    standPath.addLine(to: CGPoint(x: 594, y: 280))
    standPath.addLine(to: CGPoint(x: 554, y: 280))
    standPath.addLine(to: CGPoint(x: 544, y: 340))
    standPath.closeSubpath()
    context.addPath(standPath)
    context.setFillColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.75))
    context.fillPath()

    // Glowing Play Triangle in center of screen
    let playPath = CGMutablePath()
    let triCenter = CGPoint(x: 520, y: 500)
    playPath.move(to: CGPoint(x: triCenter.x - 36, y: triCenter.y - 48))
    playPath.addLine(to: CGPoint(x: triCenter.x + 50, y: triCenter.y))
    playPath.addLine(to: CGPoint(x: triCenter.x - 36, y: triCenter.y + 48))
    playPath.closeSubpath()

    context.addPath(playPath)
    context.setFillColor(CGColor(red: 0.35, green: 0.8, blue: 1.0, alpha: 0.95))
    context.fillPath()

    context.restoreGState()

    // Outer subtle border
    context.addPath(squirclePath)
    context.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.2))
    context.setLineWidth(4)
    context.strokePath()

    image.unlockFocus()

    // Save 1024x1024 PNG
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        print("Failed to render AppIcon")
        exit(1)
    }

    let iconsetDir = "Resources/AppIcon.iconset"
    try? FileManager.default.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

    let masterPNG = "\(iconsetDir)/icon_512x512@2x.png"
    try? png.write(to: URL(fileURLWithPath: masterPNG))

    // Generate resolutions
    let sizes = [16, 32, 128, 256, 512]
    for s in sizes {
        let p1 = "\(iconsetDir)/icon_\(s)x\(s).png"
        let p2 = "\(iconsetDir)/icon_\(s)x\(s)@2x.png"
        let task1 = Process()
        task1.launchPath = "/usr/bin/sips"
        task1.arguments = ["-z", "\(s)", "\(s)", masterPNG, "--out", p1]
        task1.launch()
        task1.waitUntilExit()

        let doubleSize = s * 2
        let task2 = Process()
        task2.launchPath = "/usr/bin/sips"
        task2.arguments = ["-z", "\(doubleSize)", "\(doubleSize)", masterPNG, "--out", p2]
        task2.launch()
        task2.waitUntilExit()
    }

    let icnsTask = Process()
    icnsTask.launchPath = "/usr/bin/iconutil"
    icnsTask.arguments = ["-c", "icns", iconsetDir, "-o", "Resources/AppIcon.icns"]
    icnsTask.launch()
    icnsTask.waitUntilExit()

    print("Generated Resources/AppIcon.icns successfully.")
}

generateAppIcon()
