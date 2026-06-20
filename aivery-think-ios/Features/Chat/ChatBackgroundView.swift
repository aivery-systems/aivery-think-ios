import SwiftUI

// Replicates the two orbiting radial gradient orbs from aivery-think's chat-container.tsx
// Orb 1: bubble-user-glow color, 80s orbit
// Orb 2: rgba(77,163,255,0.13) blue, 120s reverse orbit
struct ChatBackgroundView: View {
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var settings = UserSettings.shared
    private let startDate = Date()

    var body: some View {
        TimelineView(.periodic(from: startDate, by: 1/20)) { context in
            Canvas { ctx, size in
                let elapsed = context.date.timeIntervalSince(startDate)
                if settings.isAivery {
                    drawAivery(ctx: ctx, size: size, elapsed: elapsed)
                } else {
                    draw(ctx: ctx, size: size, elapsed: elapsed)
                }
            }
        }
        .background(baseColor)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var baseColor: Color {
        if settings.isAivery { return Color(red: 40/255, green: 46/255, blue: 120/255) }
        // --surface-recessed: #1A1C1F dark / #f7f7f8 light
        return colorScheme == .dark
            ? Color(red: 26/255, green: 28/255, blue: 31/255)
            : Color(red: 247/255, green: 247/255, blue: 248/255)
    }

    // AiVery theme: a vibrant violet→blue→teal gradient whose axis slowly rotates,
    // with two counter-orbiting radial glows for depth — echoing the app icon.
    private func drawAivery(ctx: GraphicsContext, size: CGSize, elapsed: TimeInterval) {
        let w = size.width, h = size.height
        let cx = w / 2, cy = h / 2

        let violet = Color(red: 122/255, green: 79/255,  blue: 230/255)
        let blue   = Color(red: 59/255,  green: 130/255, blue: 242/255)
        let teal   = Color(red: 30/255,  green: 182/255, blue: 149/255)

        // Rotating linear gradient axis (one full turn every 24s)
        let angle: Double = elapsed / 24 * 2 * .pi
        let reach = max(w, h)
        let dx = CGFloat(cos(angle)) * reach
        let dy = CGFloat(sin(angle)) * reach
        let start = CGPoint(x: cx + dx, y: cy + dy)
        let end   = CGPoint(x: cx - dx, y: cy - dy)
        ctx.fill(
            Path(CGRect(origin: .zero, size: size)),
            with: .linearGradient(Gradient(colors: [violet, blue, teal]),
                                  startPoint: start, endPoint: end)
        )

        // Two counter-orbiting radial glows for shimmering depth
        let orbit = w * 0.32
        let glows: [(period: Double, dir: Double, color: Color)] = [(40, 1, violet), (60, -1, teal)]
        for g in glows {
            let a: Double = elapsed / g.period * 2 * .pi * g.dir
            let ox = cx + orbit * CGFloat(cos(a))
            let oy = cy + orbit * CGFloat(sin(a))
            let r = w * 0.7
            ctx.fill(
                Path(ellipseIn: CGRect(x: ox - r, y: oy - r, width: r * 2, height: r * 2)),
                with: .radialGradient(Gradient(colors: [g.color.opacity(0.45), .clear]),
                                      center: CGPoint(x: ox, y: oy), startRadius: 0, endRadius: r)
            )
        }
    }

    private func draw(ctx: GraphicsContext, size: CGSize, elapsed: TimeInterval) {
        let w = size.width
        let h = size.height
        // Orbit radius ≈ 18% of 160% container = ~29% of screen width, matching CSS translateX(18%)
        let orbitRadius = w * 0.29

        let a1 =  (elapsed / 80)  * 2 * .pi   // 80s clockwise
        let a2 = -(elapsed / 120) * 2 * .pi   // 120s counter-clockwise

        // --bubble-user-glow: rgba(76,201,167,0.22) dark / rgba(185,167,255,0.28) light
        let glow1: Color = colorScheme == .dark
            ? Color(red: 76/255,  green: 201/255, blue: 167/255).opacity(0.22)
            : Color(red: 185/255, green: 167/255, blue: 255/255).opacity(0.28)

        // rgba(77,163,255,0.13) — same in both modes
        let glow2 = Color(red: 77/255, green: 163/255, blue: 255/255).opacity(0.13)

        // Orb 1 — 160% screen size (matches CSS width:160% height:160%)
        let cx1 = w / 2 + orbitRadius * cos(a1)
        let cy1 = h / 2 + orbitRadius * sin(a1)
        let r1  = w * 0.8  // gradient radius = 55% of ellipse 55% = ~80% of screen
        ctx.fill(
            Path(ellipseIn: CGRect(x: cx1 - r1, y: cy1 - r1, width: r1 * 2, height: r1 * 2)),
            with: .radialGradient(
                Gradient(colors: [glow1, .clear]),
                center: CGPoint(x: cx1, y: cy1),
                startRadius: 0, endRadius: r1
            )
        )

        // Orb 2 — 130% screen size (matches CSS width:130% height:130%)
        let cx2 = w / 2 + orbitRadius * cos(a2)
        let cy2 = h / 2 + orbitRadius * sin(a2)
        let r2  = w * 0.65
        ctx.fill(
            Path(ellipseIn: CGRect(x: cx2 - r2, y: cy2 - r2, width: r2 * 2, height: r2 * 2)),
            with: .radialGradient(
                Gradient(colors: [glow2, .clear]),
                center: CGPoint(x: cx2, y: cy2),
                startRadius: 0, endRadius: r2
            )
        )
    }
}
