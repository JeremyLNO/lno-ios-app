import SwiftUI

/// Minimal absolute-command SVG path parser (M/L/C/Z only — that's all the LNO
/// wordmark path uses). Lets us trace the exact same vector data as the source
/// "LNO logo v2.svg" / the web dashboard's `Logo` component (src/ui.tsx) natively,
/// instead of shipping a bitmap.
enum SVGPath {
    static func parse(_ d: String, scale: CGFloat, offset: CGPoint) -> Path {
        var path = Path()
        let scanner = Scanner(string: d)
        scanner.charactersToBeSkipped = CharacterSet(charactersIn: " ,")
        var command: Character = "M"

        func num() -> CGFloat? { scanner.scanDouble().map { CGFloat($0) } }
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * scale + offset.x, y: y * scale + offset.y) }

        while !scanner.isAtEnd {
            let before = scanner.currentIndex
            if let ch = scanner.scanCharacter() {
                if "MLCZ".contains(ch) {
                    command = ch
                    if command == "Z" { path.closeSubpath(); continue }
                } else {
                    scanner.currentIndex = before // not a command letter — it's part of a number
                }
            }
            switch command {
            case "M":
                guard let x = num(), let y = num() else { return path }
                path.move(to: pt(x, y))
            case "L":
                guard let x = num(), let y = num() else { return path }
                path.addLine(to: pt(x, y))
            case "C":
                guard let x1 = num(), let y1 = num(), let x2 = num(), let y2 = num(),
                      let x = num(), let y = num() else { return path }
                path.addCurve(to: pt(x, y), control1: pt(x1, y1), control2: pt(x2, y2))
            default:
                return path
            }
        }
        return path
    }
}

/// Vector reproduction of the official LNO mark (ascending bars + trend line +
/// "LNO" wordmark), traced from the same coordinates as the web dashboard's
/// `Logo` component and the source "LNO logo v2.svg" (viewBox 0 0 824 190.6).
/// The two gold accents (first bar + trailing dot) always stay LNO gold, exactly
/// as on the web app; everything else uses `color` (white on our dark screens).
struct LNOLogo: View {
    var color: Color = .white
    var showWordmark: Bool = true

    private static let markWidth: CGFloat = 262
    private static let fullWidth: CGFloat = 824
    private static let viewHeight: CGFloat = 190.6
    private static let wordmarkData =
        "M330.156 162.232L302 190.600L414.836 190.600L414.836 162.232ZM302 21.240L302 25.897L302 152.282L330.156 123.914L330.156 25.897L330.156 21.240Z " +
        "M566.202 21.240L566.202 122.644L453.577 21.240L453.577 64.003L594.358 190.600L594.358 190.388L594.358 190.177L594.358 21.240Z " +
        "M732.598 21.240C709.099 21.240 689.199 29.708 672.898 46.221C656.386 62.733 647.918 82.633 647.918 105.920C647.918 129.419 656.386 149.107 672.898 165.619C689.411 182.132 709.099 190.600 732.598 190.600C756.096 190.600 775.785 182.132 792.297 165.619C809.021 149.319 817.489 129.419 817.489 105.920C817.489 82.633 809.021 62.733 792.297 46.221C775.785 29.708 756.096 21.240 732.598 21.240ZM732.598 49.608C748.052 49.608 761.389 55.112 772.397 66.120C783.406 77.129 788.910 90.466 788.910 105.920C788.910 121.374 783.617 134.711 772.397 145.931C761.389 156.940 748.052 162.232 732.598 162.232C717.144 162.232 703.595 156.940 692.586 145.931C681.578 134.923 676.286 121.374 676.286 105.920C676.286 90.466 681.578 77.129 692.586 66.120C703.807 54.900 717.144 49.608 732.598 49.608Z"

    var body: some View {
        GeometryReader { geo in
            let refWidth: CGFloat = showWordmark ? Self.fullWidth : Self.markWidth
            let scale = min(geo.size.width / refWidth, geo.size.height / Self.viewHeight)
            let ox = (geo.size.width - refWidth * scale) / 2
            let oy = (geo.size.height - Self.viewHeight * scale) / 2

            bar(x: 17, y: 110.6, h: 80, scale: scale, ox: ox, oy: oy).fill(Theme.gold)
            bar(x: 77, y: 80.6, h: 110, scale: scale, ox: ox, oy: oy).fill(color)
            bar(x: 137, y: 50.6, h: 140, scale: scale, ox: ox, oy: oy).fill(color)
            bar(x: 197, y: 20.6, h: 170, scale: scale, ox: ox, oy: oy).fill(color)

            trendLine(scale: scale, ox: ox, oy: oy)
                .stroke(color, style: StrokeStyle(lineWidth: max(1.5, 6 * scale), lineCap: .round, lineJoin: .round))

            dot(cx: 7, cy: 150.6, r: 7, scale: scale, ox: ox, oy: oy).fill(color)
            dot(cx: 255, cy: 40.6, r: 7, scale: scale, ox: ox, oy: oy).fill(Theme.gold)

            if showWordmark {
                SVGPath.parse(Self.wordmarkData, scale: scale, offset: CGPoint(x: ox, y: oy))
                    .fill(color, style: FillStyle(eoFill: true))
            }
        }
    }

    private func bar(x: CGFloat, y: CGFloat, h: CGFloat, scale: CGFloat, ox: CGFloat, oy: CGFloat) -> Path {
        Path(CGRect(x: x * scale + ox, y: y * scale + oy, width: 36 * scale, height: h * scale))
    }
    private func dot(cx: CGFloat, cy: CGFloat, r: CGFloat, scale: CGFloat, ox: CGFloat, oy: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: (cx - r) * scale + ox, y: (cy - r) * scale + oy, width: r * 2 * scale, height: r * 2 * scale))
    }
    private func trendLine(scale: CGFloat, ox: CGFloat, oy: CGFloat) -> Path {
        let pts: [(CGFloat, CGFloat)] = [(7, 150.6), (35, 140.6), (95, 110.6), (155, 130.6), (215, 80.6), (255, 40.6)]
        var p = Path()
        for (i, pt) in pts.enumerated() {
            let cp = CGPoint(x: pt.0 * scale + ox, y: pt.1 * scale + oy)
            if i == 0 { p.move(to: cp) } else { p.addLine(to: cp) }
        }
        return p
    }
}

/// A pie-wedge stand-in for the Google "G" mark in the four brand colours —
/// used inside the native "Sign in with Google" button since the platform has
/// no equivalent to the web's official GIS-rendered button.
struct GoogleGMark: View {
    var size: CGFloat = 18
    var body: some View {
        ZStack {
            PieSlice(start: .degrees(-90), end: .degrees(0)).fill(Color(hex: 0x4285F4))
            PieSlice(start: .degrees(0), end: .degrees(90)).fill(Color(hex: 0x34A853))
            PieSlice(start: .degrees(90), end: .degrees(180)).fill(Color(hex: 0xFBBC05))
            PieSlice(start: .degrees(180), end: .degrees(270)).fill(Color(hex: 0xEA4335))
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
    private struct PieSlice: Shape {
        var start: Angle
        var end: Angle
        func path(in rect: CGRect) -> Path {
            var p = Path()
            let c = CGPoint(x: rect.midX, y: rect.midY)
            p.move(to: c)
            p.addArc(center: c, radius: rect.width / 2, startAngle: start, endAngle: end, clockwise: false)
            p.closeSubpath()
            return p
        }
    }
}
