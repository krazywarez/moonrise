// Renders the app icon: swift scripts/make-icon.swift App/Sources/Assets.xcassets/AppIcon.appiconset/icon-1024.png
import AppKit
import SwiftUI

struct Icon: View {
    var body: some View {
        Canvas { context, size in
            let w = size.width
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.043, green: 0.078, blue: 0.141)))
            // Stars
            let stars: [(Double, Double, Double)] = [(0.18, 0.16, 5), (0.32, 0.30, 3), (0.74, 0.14, 4), (0.86, 0.34, 3), (0.12, 0.44, 3), (0.58, 0.24, 2.5), (0.44, 0.10, 3)]
            for (x, y, r) in stars {
                context.fill(Path(ellipseIn: CGRect(x: x * w - r, y: y * w - r, width: 2 * r, height: 2 * r)), with: .color(.white.opacity(0.85)))
            }
            // Moon, rising: a waxing gibbous disc partly behind the horizon
            let c = CGPoint(x: w * 0.5, y: w * 0.60), r = w * 0.24
            context.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(Color(red: 0.16, green: 0.20, blue: 0.27)))
            var lit = Path()
            lit.move(to: CGPoint(x: c.x, y: c.y - r))
            lit.addArc(center: c, radius: r, startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: false)
            for i in 0...48 {
                let a = Double.pi / 2 - Double.pi * Double(i) / 48
                lit.addLine(to: CGPoint(x: c.x - r * 0.45 * cos(a), y: c.y + r * sin(a)))
            }
            lit.closeSubpath()
            context.fill(lit, with: .color(Color(red: 0.93, green: 0.91, blue: 0.85)))
            // Ground and horizon line
            let horizon = w * 0.70
            context.fill(Path(CGRect(x: 0, y: horizon, width: w, height: w - horizon)), with: .color(Color(red: 0.02, green: 0.035, blue: 0.06)))
            context.fill(Path(CGRect(x: 0, y: horizon - w * 0.006, width: w, height: w * 0.012)), with: .color(Color(red: 0.88, green: 0.24, blue: 0.19)))
        }
        .frame(width: 1024, height: 1024)
    }
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
MainActor.assumeIsolated {
    let renderer = ImageRenderer(content: Icon())
    renderer.scale = 1
    let cg = renderer.cgImage!
    let rep = NSBitmapImageRep(cgImage: cg)
    try! rep.representation(using: .png, properties: [:])!.write(to: out)
}
print("wrote \(out.path)")
