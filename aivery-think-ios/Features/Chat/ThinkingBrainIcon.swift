import SwiftUI

/// The web's thinking brain: two oscillating halves (squash/stretch) with rays
/// emanating left and right while active. Mirrors thinking-icon.tsx + globals.css.
struct ThinkingBrainIcon: View {
    var isActive: Bool
    @Environment(\.colorScheme) private var colorScheme

    // Matches --bubble-user: teal in dark, violet in light.
    private var activeColor: Color {
        colorScheme == .dark ? .aiveryTeal : .aiveryViolet
    }

    private let frame = CGSize(width: 28, height: 20)

    var body: some View {
        ZStack {
            if isActive {
                ForEach(Array(Self.rays.enumerated()), id: \.offset) { _, ray in
                    RayView(ray: ray)
                }
            }
            brain
        }
        .frame(width: frame.width, height: frame.height)
        .foregroundStyle(isActive ? activeColor : Color.secondary)
        .animation(.easeInOut(duration: 0.25), value: isActive)
    }

    @ViewBuilder
    private var brain: some View {
        let img = Image("ThinkingBrain")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(height: 16)

        if isActive {
            img.keyframeAnimator(initialValue: BrainAnim(), repeating: true) { view, v in
                view.scaleEffect(x: v.sx, y: v.sy, anchor: .center).opacity(v.op)
            } keyframes: { _ in
                // 2.4s loop — squash wide, stretch tall, dampen, settle.
                KeyframeTrack(\.sx) {
                    CubicKeyframe(1.28, duration: 0.24)
                    CubicKeyframe(0.87, duration: 0.288)
                    CubicKeyframe(1.08, duration: 0.24)
                    CubicKeyframe(1.0,  duration: 0.288)
                    CubicKeyframe(1.0,  duration: 1.344)
                }
                KeyframeTrack(\.sy) {
                    CubicKeyframe(0.80, duration: 0.24)
                    CubicKeyframe(1.22, duration: 0.288)
                    CubicKeyframe(0.95, duration: 0.24)
                    CubicKeyframe(1.0,  duration: 0.288)
                    CubicKeyframe(1.0,  duration: 1.344)
                }
                KeyframeTrack(\.op) {
                    LinearKeyframe(1.0,  duration: 0.24)
                    LinearKeyframe(0.9,  duration: 0.288)
                    LinearKeyframe(0.95, duration: 0.24)
                    LinearKeyframe(0.75, duration: 0.288)
                    LinearKeyframe(0.65, duration: 1.344)
                }
            }
        } else {
            img.opacity(0.7)
        }
    }

    // Ray geometry in the 28×20 design space — brain (height 16) spans x≈6…22.
    // Short stubs just outside the brain so it stays clearly brain-shaped.
    struct Ray { let p1: CGPoint; let p2: CGPoint; let dx: CGFloat; let dy: CGFloat }
    static let rays: [Ray] = [
        // Right
        Ray(p1: CGPoint(x: 22.5, y: 10), p2: CGPoint(x: 24.3, y: 10), dx: 1.4, dy: 0),
        Ray(p1: CGPoint(x: 22.2, y: 7.3), p2: CGPoint(x: 23.8, y: 5.8), dx: 1.2, dy: -1.1),
        Ray(p1: CGPoint(x: 22.2, y: 12.7), p2: CGPoint(x: 23.8, y: 14.2), dx: 1.2, dy: 1.1),
        // Left (mirror)
        Ray(p1: CGPoint(x: 5.5, y: 10), p2: CGPoint(x: 3.7, y: 10), dx: -1.4, dy: 0),
        Ray(p1: CGPoint(x: 5.8, y: 7.3), p2: CGPoint(x: 4.2, y: 5.8), dx: -1.2, dy: -1.1),
        Ray(p1: CGPoint(x: 5.8, y: 12.7), p2: CGPoint(x: 4.2, y: 14.2), dx: -1.2, dy: 1.1),
    ]
}

private struct BrainAnim {
    var sx: CGFloat = 1
    var sy: CGFloat = 1
    var op: Double = 0.65
}

private struct RayAnim {
    var op: Double = 0
    var ox: CGFloat = 0
    var oy: CGFloat = 0
}

private struct RayView: View {
    let ray: ThinkingBrainIcon.Ray

    var body: some View {
        RayShape(p1: ray.p1, p2: ray.p2)
            .stroke(style: StrokeStyle(lineWidth: 1.1, lineCap: .round))
            .keyframeAnimator(initialValue: RayAnim(), repeating: true) { view, v in
                view.opacity(v.op).offset(x: v.ox, y: v.oy)
            } keyframes: { _ in
                // appear at ~3%, fade while moving outward by 30%, rest until loop end (2.4s)
                KeyframeTrack(\.op) {
                    LinearKeyframe(0,   duration: 0.072)
                    LinearKeyframe(1,   duration: 0.0)
                    LinearKeyframe(0,   duration: 0.648)
                    LinearKeyframe(0,   duration: 1.68)
                }
                KeyframeTrack(\.ox) {
                    LinearKeyframe(0,       duration: 0.072)
                    LinearKeyframe(0,       duration: 0.0)
                    LinearKeyframe(ray.dx,  duration: 0.648)
                    LinearKeyframe(0,       duration: 1.68)
                }
                KeyframeTrack(\.oy) {
                    LinearKeyframe(0,       duration: 0.072)
                    LinearKeyframe(0,       duration: 0.0)
                    LinearKeyframe(ray.dy,  duration: 0.648)
                    LinearKeyframe(0,       duration: 1.68)
                }
            }
    }
}

private struct RayShape: Shape {
    let p1: CGPoint
    let p2: CGPoint
    func path(in rect: CGRect) -> Path {
        Path { p in p.move(to: p1); p.addLine(to: p2) }
    }
}
