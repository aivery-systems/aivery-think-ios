import SwiftUI
import Foundation
import Combine

private let PARTICLE_COUNT = 100
private let MAX_DIST: Double = 150

// MARK: - Data types

struct PlexusParticle {
    var x, y, vx, vy, r: Double
}

struct GoldRipple {
    var x, y, radius, alpha: Double
}

struct BlueRipple {
    var x, y, radius, alpha: Double
    var big: Bool
    var delay: Int
}

struct PlexusSparkle {
    var ox, oy, angle, drift, radius, speed, alpha, r: Double
    var color: (Double, Double, Double)
}

// MARK: - Simulation

final class PlexusSimulation: ObservableObject {
    private(set) var particles: [PlexusParticle] = []
    private var goldRipples: [GoldRipple] = []
    private var blueRipples: [BlueRipple] = []
    private var sparkles: [PlexusSparkle] = []
    private(set) var volatileUntil: TimeInterval = 0
    private var shimmerBlue: Double = 0
    private var shimmerGold: Double = 0
    private var lastUpdate: TimeInterval = 0
    private var initialized = false

    func ensureInitialized(size: CGSize) {
        guard !initialized, size.width > 0, size.height > 0 else { return }
        initialized = true
        for _ in 0..<PARTICLE_COUNT {
            particles.append(PlexusParticle(
                x: Double.random(in: 0..<Double(size.width)),
                y: Double.random(in: 0..<Double(size.height)),
                vx: Double.random(in: -1...1) * 0.125,
                vy: Double.random(in: -1...1) * 0.125,
                r: Double.random(in: 0.4...1.6)
            ))
        }
    }

    var isActive: Bool {
        Date().timeIntervalSinceReferenceDate < volatileUntil
            || !goldRipples.isEmpty || !blueRipples.isEmpty || !sparkles.isEmpty
    }

    // MARK: - Event triggers

    func triggerMemoryWritten() {
        volatileUntil = Date().timeIntervalSinceReferenceDate + 1.8
        guard !particles.isEmpty else { return }
        for _ in 0..<3 {
            let p = particles.randomElement()!
            goldRipples.append(GoldRipple(x: p.x, y: p.y, radius: 0, alpha: 0.9))
        }
        shimmerGold = 0.28
    }

    func triggerMemoryRetrieved(count: Int) {
        guard !particles.isEmpty, count > 0 else { return }
        let bigCount = count / 10
        let smallCount = count % 10
        for i in 0..<bigCount {
            let p = particles.randomElement()!
            blueRipples.append(BlueRipple(x: p.x, y: p.y, radius: 0, alpha: 0.85, big: true, delay: i * 6))
        }
        for i in 0..<smallCount {
            let p = particles.randomElement()!
            blueRipples.append(BlueRipple(x: p.x, y: p.y, radius: 0, alpha: 0.5, big: false, delay: bigCount * 6 + i * 3))
        }
        shimmerBlue = 0.30
    }

    // MARK: - Update (called every frame from Canvas draw closure)

    func update(date: Date, size: CGSize) {
        let now = date.timeIntervalSinceReferenceDate
        guard now - lastUpdate > 0.001 else { return }
        lastUpdate = now

        let w = Double(size.width)
        let h = Double(size.height)

        let elapsed = volatileUntil - now
        let settleT = elapsed > 0 ? min(elapsed, 0.5) / 0.5 : 0
        let speedMult = 1 + settleT * 6

        // Move particles
        for i in particles.indices {
            particles[i].x += particles[i].vx * speedMult
            particles[i].y += particles[i].vy * speedMult
            if particles[i].x < 0 { particles[i].x = w }
            if particles[i].x > w { particles[i].x = 0 }
            if particles[i].y < 0 { particles[i].y = h }
            if particles[i].y > h { particles[i].y = 0 }
        }

        // Decay shimmers
        shimmerBlue = max(0, shimmerBlue * 0.97)
        shimmerGold = max(0, shimmerGold * 0.97)

        // Gold ripples
        goldRipples = goldRipples.compactMap { var r = $0
            r.radius += 3; r.alpha *= 0.965
            return r.alpha < 0.01 ? nil : r
        }

        // Blue ripples + sparkle spawn
        for i in (0..<blueRipples.count).reversed() {
            if blueRipples[i].delay > 0 { blueRipples[i].delay -= 1; continue }

            if blueRipples[i].big && blueRipples[i].radius == 0 {
                spawnSparkles(from: blueRipples[i])
            }
            blueRipples[i].radius += blueRipples[i].big ? 4.5 : 2
            blueRipples[i].alpha *= blueRipples[i].big ? 0.974 : 0.958
            if blueRipples[i].alpha < 0.01 { blueRipples.remove(at: i) }
        }

        // Sparkles
        sparkles = sparkles.compactMap { var s = $0
            s.radius += s.speed; s.angle += s.drift; s.alpha *= 0.962
            return s.alpha < 0.01 ? nil : s
        }
    }

    private func spawnSparkles(from ripple: BlueRipple) {
        let dustColors: [(Double, Double, Double)] = [
            (210/255, 220/255, 1.0),
            (190/255, 200/255, 245/255),
            (220/255, 210/255, 250/255),
            (230/255, 235/255, 1.0),
        ]
        for s in 0..<42 {
            let angle = Double(s) / 42.0 * .pi * 2 + Double.random(in: 0...0.4)
            sparkles.append(PlexusSparkle(
                ox: ripple.x, oy: ripple.y,
                angle: angle,
                drift: Double.random(in: -0.022...0.022),
                radius: 0,
                speed: 4.5 + Double.random(in: -1...1),
                alpha: 0.5 + Double.random(in: 0...0.5),
                r: 0.5 + Double.random(in: 0...2.5),
                color: dustColors.randomElement()!
            ))
        }
    }

    // MARK: - Draw

    func draw(in ctx: GraphicsContext, size: CGSize, isDark: Bool) {
        let w = size.width
        let h = size.height

        // Shimmer glow overlays
        if shimmerBlue > 0.001 {
            let c: Color = isDark ? Color(red: 80/255, green: 170/255, blue: 1) : Color(red: 110/255, green: 80/255, blue: 210/255)
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .radialGradient(
                Gradient(colors: [c.opacity(shimmerBlue), .clear]),
                center: CGPoint(x: w / 2, y: h / 2),
                startRadius: 0, endRadius: max(w, h) * 0.55
            ))
        }
        if shimmerGold > 0.001 {
            let c: Color = isDark ? Color(red: 1, green: 200/255, blue: 50/255) : Color(red: 220/255, green: 140/255, blue: 20/255)
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .radialGradient(
                Gradient(colors: [c.opacity(shimmerGold), .clear]),
                center: CGPoint(x: w / 2, y: h / 2),
                startRadius: 0, endRadius: max(w, h) * 0.55
            ))
        }

        // Particle connection lines — batched into alpha buckets for performance
        let lineAlphaScale = isDark ? 0.12 : 0.30
        let lineWidth: CGFloat = isDark ? 0.5 : 0.3
        let lineColor: Color = isDark
            ? Color(red: 100/255, green: 180/255, blue: 1)
            : Color(red: 110/255, green: 80/255, blue: 210/255)

        let buckets = 8
        var paths = Array(repeating: Path(), count: buckets)

        for i in 0..<particles.count {
            for j in (i+1)..<particles.count {
                let dx = particles[i].x - particles[j].x
                let dy = particles[i].y - particles[j].y
                let distSq = dx*dx + dy*dy
                if distSq < MAX_DIST * MAX_DIST {
                    let dist = distSq.squareRoot()
                    let alpha = (1 - dist / MAX_DIST) * lineAlphaScale
                    let bucket = min(Int(alpha / lineAlphaScale * Double(buckets)), buckets - 1)
                    paths[bucket].move(to: CGPoint(x: particles[i].x, y: particles[i].y))
                    paths[bucket].addLine(to: CGPoint(x: particles[j].x, y: particles[j].y))
                }
            }
        }
        for (b, path) in paths.enumerated() {
            let alpha = Double(b + 1) / Double(buckets) * lineAlphaScale
            ctx.stroke(path, with: .color(lineColor.opacity(alpha)), lineWidth: lineWidth)
        }

        // Dots
        let dotColor: Color = isDark
            ? Color(red: 130/255, green: 195/255, blue: 1, opacity: 0.35)
            : Color(red: 130/255, green: 90/255, blue: 220/255)
        let dotScale: Double = isDark ? 1.0 : 1.4
        for p in particles {
            let r = p.r * dotScale
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r*2, height: r*2)), with: .color(dotColor))
        }

        // Gold ripples (memory written)
        for rip in goldRipples {
            var path = Path()
            path.addEllipse(in: CGRect(x: rip.x - rip.radius, y: rip.y - rip.radius, width: rip.radius*2, height: rip.radius*2))
            ctx.stroke(path, with: .color(Color(red: 1, green: 200/255, blue: 50/255, opacity: rip.alpha)), lineWidth: 1.5)
        }

        // Blue ripples (memory retrieved)
        for rip in blueRipples where rip.delay == 0 {
            var path = Path()
            path.addEllipse(in: CGRect(x: rip.x - rip.radius, y: rip.y - rip.radius, width: rip.radius*2, height: rip.radius*2))
            ctx.stroke(path, with: .color(Color(red: 80/255, green: 170/255, blue: 1, opacity: rip.alpha)), lineWidth: rip.big ? 2.5 : 0.9)
        }

        // Sparkles (dust from big blue ripples)
        for sp in sparkles {
            let sx = sp.ox + cos(sp.angle) * sp.radius
            let sy = sp.oy + sin(sp.angle) * sp.radius
            let c = Color(red: sp.color.0, green: sp.color.1, blue: sp.color.2, opacity: sp.alpha)
            let glow = Color(red: sp.color.0, green: sp.color.1, blue: sp.color.2, opacity: sp.alpha * 0.6)
            let rect = CGRect(x: sx - sp.r, y: sy - sp.r, width: sp.r * 2, height: sp.r * 2)
            ctx.drawLayer { l in
                l.addFilter(.shadow(color: glow, radius: 4 + sp.r * 3, x: 0, y: 0))
                l.fill(Path(ellipseIn: rect), with: .color(c))
            }
        }
    }
}
