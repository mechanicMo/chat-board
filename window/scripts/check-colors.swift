// Checks a board snapshot for status bars in all four colors.
//   swift scripts/check-colors.swift <snapshot.png> <width in points>
//
// 1. Finds the status bar column: of the columns 8 to 26 points from the left edge, the one with the most
//    strongly colored pixels (the 3-point bar every top-level row starts with).
// 2. Walks down that one column and groups the pixels into runs of the same family:
//      purple  hue 255-325°, saturation > 0.25
//      orange  hue 15-50°,   saturation > 0.25
//      green   hue 85-165°,  saturation > 0.25
//      gray    saturation < 0.12 and brightness 0.03-0.30 away from the background (the top-left pixel),
//              which leaves out the background itself and the white bar of the current chat
// 3. A family counts only if it has a run at least 20 points tall. Bars are about 40 points tall, while the
//    color key's dots are 10, so the key can't pass the check on its own.
// Exits 0 when all four families are found, 1 otherwise.
import CoreGraphics
import Foundation
import ImageIO

let arguments = CommandLine.arguments
guard arguments.count == 3, let points = Double(arguments[2]), points > 0 else {
    FileHandle.standardError.write(Data("usage: check-colors.swift <png> <width in points>\n".utf8))
    exit(2)
}
guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: arguments[1]) as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
    print("FAIL: can't read \(arguments[1])")
    exit(1)
}

// Redraw into a known RGBA layout so any PNG flavor reads the same.
let width = image.width, height = image.height
var pixels = [UInt8](repeating: 0, count: width * height * 4)
let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
let scale = Double(width) / points

// Row 0 is the top of the image.
func rgb(_ x: Int, _ y: Int) -> (Double, Double, Double) {
    let i = (y * width + x) * 4
    return (Double(pixels[i]) / 255, Double(pixels[i + 1]) / 255, Double(pixels[i + 2]) / 255)
}

func hsv(_ c: (Double, Double, Double)) -> (h: Double, s: Double, v: Double) {
    let (r, g, b) = c
    let high = max(r, g, b), low = min(r, g, b), delta = high - low
    var hue = 0.0
    if delta > 0 {
        if high == r { hue = 60 * ((g - b) / delta).truncatingRemainder(dividingBy: 6) }
        else if high == g { hue = 60 * ((b - r) / delta + 2) }
        else { hue = 60 * ((r - g) / delta + 4) }
    }
    if hue < 0 { hue += 360 }
    return (hue, high == 0 ? 0 : delta / high, high)
}

let background = hsv(rgb(0, 0)).v

func family(_ x: Int, _ y: Int) -> String? {
    let (h, s, v) = hsv(rgb(x, y))
    if s > 0.25, v > 0.15 {
        if (255...325).contains(h) { return "purple" }
        if (15...50).contains(h) { return "orange" }
        if (85...165).contains(h) { return "green" }
        return nil
    }
    let distance = abs(v - background)
    if s < 0.12, distance >= 0.03, distance <= 0.30 { return "gray" }
    return nil
}

let firstColumn = Int(8 * scale), lastColumn = min(width - 1, Int(26 * scale))
guard firstColumn < lastColumn else { print("FAIL: image too narrow"); exit(1) }
let column = (firstColumn...lastColumn).max { a, b in
    let count = { (x: Int) in (0..<height).filter { y in let f = family(x, y); return f != nil && f != "gray" }.count }
    return count(a) < count(b)
}!

var longest: [String: Int] = [:]
var current: String?, run = 0
for y in 0..<height {
    let f = family(column, y)
    run = f == current ? run + 1 : 1
    current = f
    if let f { longest[f] = max(longest[f] ?? 0, run) }
}

let needed = Int(20 * scale)
var ok = true
print("status bar column: x=\(column) px (\(String(format: "%.1f", Double(column) / scale)) pt), scale \(scale)x, background brightness \(String(format: "%.2f", background))")
for name in ["purple", "orange", "green", "gray"] {
    let tallest = longest[name] ?? 0
    let found = tallest >= needed
    ok = ok && found
    print("  \(name): tallest run \(String(format: "%.0f", Double(tallest) / scale)) pt -> \(found ? "found" : "MISSING")")
}
print(ok ? "PASS: all four status colors are in the status bar column" : "FAIL: a status color is missing")
exit(ok ? 0 : 1)
