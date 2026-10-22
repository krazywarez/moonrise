// Milky Way brightness on a 2° equatorial grid from ESA's "Gaia's sky in colour" (ESA/Gaia/DPAC, CC BY-SA 3.0 IGO),
// a Hammer–Aitoff map in galactic coordinates with longitude increasing to the left.
//
//     swift scripts/make-milkyway.swift Gaia_s_sky_in_colour.jpg
//
// Writes Packages/MoonriseKit/Sources/SkyRenderer/Resources/milkyway.bin: 180 × 90 bytes, rows from Dec −89° to
// +89°, columns from RA 1° to 359°, each the cell's brightness above the high-latitude sky, scaled so the
// 99.5th percentile is 255. The file is an adaptation of the image and is under the same licence.
import CoreGraphics
import Foundation
import ImageIO

let input = URL(fileURLWithPath: CommandLine.arguments[1])
let source = CGImageSourceCreateWithURL(input as CFURL, nil)!
let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
let w = image.width, h = image.height
var pixels = [UInt8](repeating: 0, count: w * h * 4)
let context = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

func luminance(_ x: Int, _ y: Int) -> Double {
    let i = (y * w + x) * 4
    return (0.2126 * Double(pixels[i]) + 0.7152 * Double(pixels[i + 1]) + 0.0722 * Double(pixels[i + 2])) / 255
}

// The map's ellipse: the extent of pixels brighter than the black surround along the middle row and column.
let midY = h / 2, midX = w / 2
let xs = (0..<w).filter { luminance($0, midY) > 0.05 }, ys = (0..<h).filter { luminance(midX, $0) > 0.05 }
let cx = Double(xs.first! + xs.last!) / 2, cy = Double(ys.first! + ys.last!) / 2
let ax = Double(xs.last! - xs.first!) / 2, ay = Double(ys.last! - ys.first!) / 2
print("ellipse centre", cx, cy, "semi-axes", ax, ay)

let r = Double.pi / 180
/// J2000 equatorial to galactic (IAU 1958 pole at RA 192.85948°, Dec 27.12825°; node 32.93192°).
func galactic(ra: Double, dec: Double) -> (l: Double, b: Double) {
    let a0 = 192.85948 * r, d0 = 27.12825 * r, l0 = 122.93192 * r
    let a = ra * r, d = dec * r
    let sinb = sin(d) * sin(d0) + cos(d) * cos(d0) * cos(a - a0)
    let y = cos(d) * sin(a - a0), x = sin(d) * cos(d0) - cos(d) * sin(d0) * cos(a - a0)
    return ((l0 - atan2(y, x)) / r, asin(sinb) / r)
}

/// Mean luminance in a 5 × 5 patch at the Hammer–Aitoff position of (l, b).
func sample(l: Double, b: Double) -> Double {
    let lw = remainder(l, 360) * r, bb = b * r
    let z = (1 + cos(bb) * cos(lw / 2)).squareRoot()
    let x = 2 * 2.0.squareRoot() * cos(bb) * sin(lw / 2) / z, y = 2.0.squareRoot() * sin(bb) / z
    let px = Int(cx - x / (2 * 2.0.squareRoot()) * ax), py = Int(cy - y / 2.0.squareRoot() * ay)
    var sum = 0.0, n = 0.0
    for dy in -2...2 { for dx in -2...2 {
        let qx = min(max(px + dx, 0), w - 1), qy = min(max(py + dy, 0), h - 1)
        sum += luminance(qx, qy); n += 1
    } }
    return sum / n
}

var raw: [Double] = [], high: [Double] = []
for row in 0..<90 {
    let dec = -89 + 2 * Double(row)
    for col in 0..<180 {
        let ra = 1 + 2 * Double(col)
        let g = galactic(ra: ra, dec: dec)
        let v = sample(l: g.l, b: g.b)
        raw.append(v)
        if abs(g.b) > 60 { high.append(v) }
    }
}
let floor = high.sorted()[high.count / 2]
let above = raw.map { max(0, $0 - floor) }
let top = above.sorted()[Int(Double(above.count) * 0.995)]
let bytes = above.map { UInt8(min(255, ($0 / top * 255).rounded())) }
let out = URL(fileURLWithPath: "Packages/MoonriseKit/Sources/SkyRenderer/Resources/milkyway.bin")
try! Data(bytes).write(to: out)
print("floor", floor, "top", top, "cells over 40:", bytes.filter { $0 > 40 }.count)
