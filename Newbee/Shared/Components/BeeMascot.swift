import SwiftUI

/// The bee from the app icon ("Milk Drop Flyby"), small and decorative. It sits beside things,
/// never in front of them: empty states, the Home header, the timer, Feed saved, onboarding and
/// Night Shift. Always hidden from VoiceOver.
///
/// - `hovering`: wings flutter and the bee bobs gently.
/// - `resting`: wings still.
/// - `sleeping`: eye closed, wings folded, a small "z". Used at night.
///
/// With Reduce Motion the bee is a still picture. In dark mode it is a little dimmer so it never
/// glows at 3 a.m.
struct BeeMascot: View {
    enum Pose { case hovering, resting, sleeping }

    var pose: Pose = .hovering
    /// Width of the bee in points. The height is about 0.9 of it.
    var size: CGFloat = 40
    /// Faces left instead of right.
    var flipped = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || pose != .hovering)) { context in
            let t = reduceMotion || pose != .hovering ? 0 : context.date.timeIntervalSinceReferenceDate
            Canvas { canvas, canvasSize in
                BeeDrawing.draw(in: &canvas, size: canvasSize, pose: pose, time: t, flipped: flipped)
            }
            .offset(y: Self.bob(pose: pose, time: t, size: size))
        }
        .frame(width: size, height: size * BeeDrawing.aspect)
        .overlay(alignment: flipped ? .topLeading : .topTrailing) {
            if pose == .sleeping {
                Text(verbatim: "z")
                    .font(.system(size: max(size * 0.28, 9), weight: .bold, design: .rounded))
                    .foregroundStyle(BeeDrawing.ink.opacity(colorScheme == .dark ? 0.6 : 0.45))
                    .offset(x: flipped ? -size * 0.12 : size * 0.12, y: -size * 0.18)
            }
        }
        .opacity(colorScheme == .dark ? 0.82 : 1)
        .saturation(colorScheme == .dark ? 0.85 : 1)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    private static func bob(pose: Pose, time: TimeInterval, size: CGFloat) -> CGFloat {
        switch pose {
        case .hovering: sin(time * 2 * .pi / 2.4) * size * 0.05
        case .resting, .sleeping: 0
        }
    }
}

extension View {
    /// The bee flies in once along a gentle curve when this view first appears, then stays put.
    /// Nothing moves with Reduce Motion.
    func beeFlyIn(from start: CGSize = CGSize(width: -90, height: 50), delay: Double = 0.25) -> some View {
        modifier(BeeFlyIn(start: start, delay: delay))
    }
}

private struct BeeFlyIn: ViewModifier {
    let start: CGSize
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var arrived = false

    func body(content: Content) -> some View {
        let away = !arrived && !reduceMotion
        content
            .offset(away ? start : .zero)
            .rotationEffect(.degrees(away ? -14 : 0))
            .opacity(away ? 0 : 1)
            .onAppear {
                guard !arrived else { return }
                withAnimation(.spring(duration: 1.3, bounce: 0.25).delay(delay)) { arrived = true }
            }
    }
}

/// Draws the bee with the same shapes as the icon's SVG (app-store/icon-concepts/svg), in
/// the icon's coordinate space: x -210...190, y -235...135, body centered on the origin.
enum BeeDrawing {
    static let minX: CGFloat = -210, maxX: CGFloat = 190
    static let minY: CGFloat = -235, maxY: CGFloat = 135
    static let aspect = (maxY - minY) / (maxX - minX)

    static let ink = Color(red: 0x3B / 255, green: 0x2F / 255, blue: 0x4A / 255)
    private static let bodyLight = Color(red: 1, green: 0xE0 / 255, blue: 0x7A / 255)
    private static let bodyMid = Color(red: 1, green: 0xC9 / 255, blue: 0x3C / 255)
    private static let bodyDark = Color(red: 1, green: 0xB3 / 255, blue: 0x20 / 255)
    private static let wingEdge = Color(red: 0xC4 / 255, green: 0xD9 / 255, blue: 0xF0 / 255)
    private static let cheek = Color(red: 1, green: 0x8F / 255, blue: 0xA3 / 255)

    static func draw(in canvas: inout GraphicsContext, size: CGSize, pose: BeeMascot.Pose, time: TimeInterval, flipped: Bool) {
        let scale = min(size.width / (maxX - minX), size.height / (maxY - minY))
        var ctx = canvas
        if flipped {
            ctx.translateBy(x: size.width, y: 0)
            ctx.scaleBy(x: -1, y: 1)
        }
        ctx.translateBy(x: -minX * scale, y: -minY * scale)
        ctx.scaleBy(x: scale, y: scale)
        ctx.rotate(by: .degrees(-12))

        // Wings behind the body. Hovering: a soft flutter (not a real bee's blur, which would
        // be too busy). Resting: still. Sleeping: folded a little lower.
        let flutter: CGFloat = switch pose {
        case .hovering: 0.72 + 0.28 * abs(sin(time * 2 * .pi * 3.2))
        case .resting: 1
        case .sleeping: 0.82
        }
        let lineWidth: CGFloat = 9
        drawWing(ctx, center: CGPoint(x: -30, y: -125), rx: 70, ry: 100, angle: -22, squash: flutter, lineWidth: lineWidth)
        drawWing(ctx, center: CGPoint(x: 40, y: -120), rx: 60, ry: 88, angle: 18, squash: flutter, lineWidth: lineWidth)

        // Antenna.
        var antenna = Path()
        antenna.move(to: CGPoint(x: 95, y: -85))
        antenna.addQuadCurve(to: CGPoint(x: 160, y: -175), control: CGPoint(x: 110, y: -150))
        ctx.stroke(antenna, with: .color(ink), style: StrokeStyle(lineWidth: 14, lineCap: .round))
        ctx.fill(Path(ellipseIn: CGRect(x: 138, y: -197, width: 44, height: 44)), with: .color(ink))

        // Stinger.
        var stinger = Path()
        stinger.move(to: CGPoint(x: -158, y: -8))
        stinger.addLine(to: CGPoint(x: -200, y: 6))
        stinger.addLine(to: CGPoint(x: -156, y: 22))
        stinger.closeSubpath()
        ctx.fill(stinger, with: .color(ink))

        // Body with its two stripes.
        let bodyRect = CGRect(x: -165, y: -125, width: 330, height: 250)
        let body = Path(ellipseIn: bodyRect)
        ctx.fill(body, with: .radialGradient(
            Gradient(stops: [.init(color: bodyLight, location: 0), .init(color: bodyMid, location: 0.6), .init(color: bodyDark, location: 1)]),
            center: CGPoint(x: -33, y: -37), startRadius: 0, endRadius: 250
        ))
        var stripes = ctx
        stripes.clip(to: body)
        var stripe1 = Path()
        stripe1.move(to: CGPoint(x: -70, y: -140))
        stripe1.addQuadCurve(to: CGPoint(x: -70, y: 140), control: CGPoint(x: -50, y: 0))
        stripe1.addLine(to: CGPoint(x: -120, y: 140))
        stripe1.addQuadCurve(to: CGPoint(x: -120, y: -140), control: CGPoint(x: -100, y: 0))
        stripe1.closeSubpath()
        stripes.fill(stripe1, with: .color(ink))
        stripes.fill(stripe1.offsetBy(dx: 80, dy: 0), with: .color(ink))

        // Face: eye (or a closed-eye curve), cheek, smile.
        if pose == .sleeping {
            var closed = Path()
            closed.move(to: CGPoint(x: 76, y: -10))
            closed.addQuadCurve(to: CGPoint(x: 114, y: -10), control: CGPoint(x: 95, y: 6))
            ctx.stroke(closed, with: .color(ink), style: StrokeStyle(lineWidth: 10, lineCap: .round))
        } else {
            ctx.fill(Path(ellipseIn: CGRect(x: 73, y: -42, width: 44, height: 60)), with: .color(ink))
            ctx.fill(Path(ellipseIn: CGRect(x: 94, y: -30, width: 16, height: 16)), with: .color(.white))
        }
        ctx.fill(Path(ellipseIn: CGRect(x: 92, y: 22, width: 52, height: 32)), with: .color(cheek.opacity(0.6)))
        var smile = Path()
        smile.move(to: CGPoint(x: 80, y: 40))
        smile.addQuadCurve(to: CGPoint(x: 128, y: 44), control: CGPoint(x: 100, y: 62))
        ctx.stroke(smile, with: .color(ink), style: StrokeStyle(lineWidth: 11, lineCap: .round))
    }

    /// One wing: an ellipse rotated by `angle`, squashed toward its base (the body) by `squash`.
    private static func drawWing(_ ctx: GraphicsContext, center: CGPoint, rx: CGFloat, ry: CGFloat, angle: Double, squash: CGFloat, lineWidth: CGFloat) {
        var wing = ctx
        // Rotate about the ellipse's center, as the SVG does, then squash toward the wing's
        // base (the bottom of the ellipse, where it meets the body).
        wing.translateBy(x: center.x, y: center.y)
        wing.rotate(by: .degrees(angle))
        wing.translateBy(x: 0, y: ry)
        wing.scaleBy(x: 1, y: squash)
        let shape = Path(ellipseIn: CGRect(x: -rx, y: -2 * ry, width: 2 * rx, height: 2 * ry))
        wing.fill(shape, with: .color(.white.opacity(0.95)))
        wing.stroke(shape, with: .color(wingEdge), lineWidth: lineWidth)
    }
}

#Preview("Poses") {
    VStack(spacing: 32) {
        HStack(spacing: 32) {
            BeeMascot(pose: .hovering, size: 80)
            BeeMascot(pose: .resting, size: 80)
            BeeMascot(pose: .sleeping, size: 80)
        }
        HStack(spacing: 24) {
            BeeMascot(size: 24)
            BeeMascot(size: 32, flipped: true)
            BeeMascot(size: 48).beeFlyIn()
        }
    }
    .padding()
}
