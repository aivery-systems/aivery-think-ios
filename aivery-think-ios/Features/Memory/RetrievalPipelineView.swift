import SwiftUI

struct RetrievalPipelineView: View {
    let stages: [RetrievalStageEvent]

    private let pipeline: [(key: String, label: String)] = [
        ("embedding",    "Embed"),
        ("clusterFilter","Cluster"),
        ("vectorSearch", "Search"),
        ("dbFetch",      "Fetch"),
        ("ranked",       "Ranked"),
    ]

    private func isComplete(_ key: String) -> Bool {
        stages.contains { $0.stage == key }
    }

    private func countFor(_ key: String) -> Int? {
        stages.first { $0.stage == key }?.count
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(pipeline.enumerated()), id: \.offset) { idx, step in
                VStack(spacing: 5) {
                    Circle()
                        .fill(isComplete(step.key) ? Color.accentColor : Color(.systemFill))
                        .frame(width: 10, height: 10)
                        .overlay(
                            Circle().stroke(Color.accentColor.opacity(0.4), lineWidth: 1)
                        )

                    Text(step.label)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(isComplete(step.key) ? .primary : .tertiary)

                    if let count = countFor(step.key) {
                        Text("\(count)")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("—")
                            .font(.system(size: 9))
                            .foregroundStyle(.quaternary)
                    }
                }
                .frame(maxWidth: .infinity)

                if idx < pipeline.count - 1 {
                    Rectangle()
                        .fill(isComplete(step.key) && isComplete(pipeline[idx + 1].key)
                              ? Color.accentColor : Color(.systemFill))
                        .frame(height: 1.5)
                        .offset(y: -12) // align with dot center
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
