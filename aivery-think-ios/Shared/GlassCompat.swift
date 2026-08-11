import SwiftUI

/// Gates Liquid Glass UI to OS versions where it's supported/approved for this app.
/// Below `minimumVersion`, callers fall back to standard Material-based chrome so the
/// app stays fully functional (no broken/half-rendered glass) with graceful visual
/// degradation instead.
enum GlassSupport {
    static let minimumVersion = OperatingSystemVersion(majorVersion: 26, minorVersion: 5, patchVersion: 0)

    static var isAvailable: Bool {
        ProcessInfo.processInfo.isOperatingSystemAtLeast(minimumVersion)
    }
}

extension View {
    /// Liquid Glass on supported OS versions; a Material fill + hairline stroke elsewhere.
    /// `interactive` mirrors `.glassEffect(.regular.interactive())`'s tap/press response —
    /// the fallback has no equivalent, so it's accepted and ignored there.
    @ViewBuilder
    func glassEffectCompat<S: InsettableShape>(interactive: Bool = false, in shape: S) -> some View {
        if #available(iOS 26.0, *), GlassSupport.isAvailable {
            if interactive {
                self.glassEffect(.regular.interactive(), in: shape)
            } else {
                self.glassEffect(.regular, in: shape)
            }
        } else {
            self
                .background(.regularMaterial, in: shape)
                .overlay(shape.strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
        }
    }
}

/// Fallback for `GlassEffectContainer`, whose only job is coordinating morph/merge
/// transitions between sibling `.glassEffect` views — nothing to reproduce when those
/// siblings are already rendering as plain Material shapes.
struct GlassEffectContainerCompat<Content: View>: View {
    var spacing: CGFloat = 0
    @ViewBuilder var content: () -> Content

    var body: some View {
        if #available(iOS 26.0, *), GlassSupport.isAvailable {
            GlassEffectContainer(spacing: spacing, content: content)
        } else {
            content()
        }
    }
}
