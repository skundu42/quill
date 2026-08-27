import SwiftUI

enum QuillBrand {
    static let ink = Color(red: 17 / 255, green: 19 / 255, blue: 18 / 255)
    static let signal = Color(red: 221 / 255, green: 255 / 255, blue: 197 / 255)
}

struct QuillLogoView: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.234, style: .continuous)
                .fill(QuillBrand.ink)
            QuillNibShape()
                .fill(QuillBrand.signal)
                .padding(size * 0.16)
            QuillStrokeShape()
                .stroke(.white, style: StrokeStyle(lineWidth: size * 0.039, lineCap: .round))
                .padding(size * 0.16)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.12), radius: size * 0.2, y: size * 0.09)
        .accessibilityHidden(true)
    }
}

struct QuillNibMark: View {
    var color: Color = .primary

    var body: some View {
        QuillNibShape()
            .fill(color)
            .aspectRatio(1, contentMode: .fit)
            .accessibilityHidden(true)
    }
}

private struct QuillNibShape: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 36
        let sy = rect.height / 36
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * sx, y: rect.minY + y * sy)
        }

        var path = Path()
        path.move(to: point(26.8, 8.5))
        path.addCurve(to: point(13.2, 17.6), control1: point(20.6, 9.9), control2: point(16.0, 12.9))
        path.addCurve(to: point(10.9, 26.9), control1: point(11.4, 20.6), control2: point(10.6, 23.7))
        path.addLine(to: point(15.5, 22.1))
        path.addLine(to: point(18.7, 21.9))
        path.addLine(to: point(16.3, 20.6))
        path.addLine(to: point(19.7, 17.0))
        path.addLine(to: point(23.0, 16.9))
        path.addLine(to: point(20.6, 15.5))
        path.addCurve(to: point(26.8, 8.5), control1: point(22.7, 13.3), control2: point(25.0, 10.9))
        path.closeSubpath()
        return path
    }
}

private struct QuillStrokeShape: Shape {
    func path(in rect: CGRect) -> Path {
        let sx = rect.width / 36
        let sy = rect.height / 36
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 9.9 * sx, y: rect.minY + 29.3 * sy))
        path.addCurve(
            to: CGPoint(x: rect.minX + 21.7 * sx, y: rect.minY + 15.3 * sy),
            control1: CGPoint(x: rect.minX + 13.3 * sx, y: rect.minY + 24.0 * sy),
            control2: CGPoint(x: rect.minX + 17.2 * sx, y: rect.minY + 19.3 * sy)
        )
        return path
    }
}
