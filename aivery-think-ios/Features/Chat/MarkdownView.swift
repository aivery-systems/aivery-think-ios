import SwiftUI

// MARK: - Segment parser

private enum MDSegment {
    case text(String)
    case code(lang: String, body: String)
}

private func parseSegments(_ raw: String) -> [MDSegment] {
    var segments: [MDSegment] = []
    var remaining = raw[raw.startIndex...]

    while let fenceStart = remaining.range(of: "```") {
        let before = String(remaining[..<fenceStart.lowerBound])
        if !before.isEmpty { segments.append(.text(before)) }

        let afterFence = remaining[fenceStart.upperBound...]
        let lineEnd = afterFence.firstIndex(of: "\n") ?? afterFence.endIndex
        let lang = String(afterFence[..<lineEnd]).trimmingCharacters(in: .whitespaces)

        let bodyStart = lineEnd < afterFence.endIndex
            ? afterFence.index(after: lineEnd) : afterFence.endIndex
        let bodySlice = afterFence[bodyStart...]

        if let closingFence = bodySlice.range(of: "```") {
            var body = String(bodySlice[..<closingFence.lowerBound])
            if body.hasSuffix("\n") { body = String(body.dropLast()) }
            segments.append(.code(lang: lang, body: body))
            remaining = bodySlice[closingFence.upperBound...]
        } else {
            segments.append(.code(lang: lang, body: String(bodySlice)))
            remaining = bodySlice[bodySlice.endIndex...]
        }
    }

    if !remaining.isEmpty { segments.append(.text(String(remaining))) }
    return segments
}

// MARK: - Markdown content view

struct MarkdownContentView: View {
    let text: String

    private var segments: [MDSegment] { parseSegments(text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                switch seg {
                case .text(let s):
                    inlineText(s)
                case .code(let lang, let body):
                    CodeBlockView(lang: lang, code: body)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func inlineText(_ s: String) -> some View {
        let trimmed = s.trimmingCharacters(in: .newlines)
        if trimmed.isEmpty { EmptyView() }
        else if let attr = try? AttributedString(
            markdown: trimmed,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            Text(attr)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(trimmed)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Code block

struct CodeBlockView: View {
    let lang: String
    let code: String

    @State private var copied = false
    @Environment(\.colorScheme) private var colorScheme

    private var bgColor: Color {
        colorScheme == .dark
            ? Color(white: 0.12)
            : Color(white: 0.93)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header bar: language label + copy button
            HStack {
                if !lang.isEmpty {
                    Text(lang)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .textCase(.lowercase)
                }
                Spacer()
                Button {
                    UIPasteboard.general.string = code
                    copied = true
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(copied ? Color.accentColor : .secondary)
                        .animation(.easeInOut(duration: 0.2), value: copied)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(bgColor.opacity(0.6))

            Divider().opacity(0.3)

            // Code body — horizontally scrollable
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.primary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .background(bgColor)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.primary.opacity(0.08), lineWidth: 1)
        )
    }
}
