import SwiftUI

struct PlexusView: View {
    @Environment(\.colorScheme) private var colorScheme
    let retrievedCount: Int
    let writtenCount: Int

    @StateObject private var sim = PlexusSimulation()
    @State private var isActive = false
    @State private var deactivateTask: Task<Void, Never>?

    var body: some View {
        Group {
            if isActive {
                TimelineView(.animation) { tl in
                    canvas(date: tl.date)
                }
            } else {
                TimelineView(.periodic(from: .now, by: 1 / 8)) { tl in
                    canvas(date: tl.date)
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onChange(of: retrievedCount) {
            sim.triggerMemoryRetrieved(count: retrievedCount)
            activate()
        }
        .onChange(of: writtenCount) {
            sim.triggerMemoryWritten()
            activate()
        }
    }

    private func canvas(date: Date) -> some View {
        Canvas { ctx, size in
            sim.ensureInitialized(size: size)
            sim.update(date: date, size: size)
            sim.draw(in: ctx, size: size, isDark: colorScheme == .dark)
        }
    }

    private func activate() {
        isActive = true
        // Cancel any pending deactivation before scheduling a new one — prevents
        // multiple asyncAfter closures stacking up and holding sim alive redundantly.
        deactivateTask?.cancel()
        deactivateTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            if !sim.isActive { isActive = false }
        }
    }
}
