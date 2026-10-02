// Генерация иконки приложения 1024x1024 в фирменном стиле ClevVPN.
// Запуск: swift scripts/generate-appicon.swift <output.png>
import AppKit

let size: CGFloat = 1024
let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "ClevVPN/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon1024.png"

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

guard let ctx = NSGraphicsContext.current?.cgContext else {
    fatalError("no graphics context")
}

// Чёрный фон
ctx.setFillColor(NSColor(srgbRed: 0.02, green: 0.02, blue: 0.03, alpha: 1).cgColor)
ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

let light = NSColor(srgbRed: 1.0, green: 0.769, blue: 0.0, alpha: 1).cgColor   // #FFC400
let dark = NSColor(srgbRed: 0.82, green: 0.529, blue: 0.0, alpha: 1).cgColor   // #D18700

// Геометрия W (в системе координат AppKit ось Y вверх)
let unit = size / 140                       // логотип ~100 единиц шириной по центру
let offsetX = (size - 100 * unit) / 2
let topY = size - (size - 66 * unit) / 2 - 18 * unit
let bottomY = (size - 66 * unit) / 2 + 10 * unit
let dotY = topY + 11 * unit
let dotR = 4.2 * unit
let barWidth = 15 * unit

let peaks: [CGFloat] = [11, 50, 89].map { offsetX + $0 * unit }
let valleys: [CGFloat] = [30.5, 69.5].map { offsetX + $0 * unit }

func bar(from: CGPoint, to: CGPoint, color: CGColor) {
    ctx.setStrokeColor(color)
    ctx.setLineWidth(barWidth)
    ctx.setLineCap(.round)
    ctx.move(to: from)
    ctx.addLine(to: to)
    ctx.strokePath()
}

// Тёмные ленты под светлыми
bar(from: CGPoint(x: valleys[0], y: bottomY), to: CGPoint(x: peaks[1], y: topY), color: dark)
bar(from: CGPoint(x: valleys[1], y: bottomY), to: CGPoint(x: peaks[2], y: topY), color: dark)
bar(from: CGPoint(x: peaks[0], y: topY), to: CGPoint(x: valleys[0], y: bottomY), color: light)
bar(from: CGPoint(x: peaks[1], y: topY), to: CGPoint(x: valleys[1], y: bottomY), color: light)

ctx.setFillColor(light)
for x in peaks {
    ctx.fillEllipse(in: CGRect(x: x - dotR, y: dotY - dotR, width: dotR * 2, height: dotR * 2))
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("failed to render png")
}
try png.write(to: URL(fileURLWithPath: outputPath))
print("written: \(outputPath)")
