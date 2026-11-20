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

// MARK: - Rendered segments (cached)

/// A segment with its inline markdown + LaTeX already rendered. Building the
/// AttributedString (LaTeX regex passes + markdown parse) is the expensive part of a
/// bubble, so it happens once per distinct text, not on every SwiftUI render.
private enum RenderedSegment {
    case text(AttributedString?, plain: String)
    case code(lang: String, body: String)
}

private final class RenderedBox {
    let segments: [RenderedSegment]
    init(_ s: [RenderedSegment]) { segments = s }
}

private let renderedCache: NSCache<NSString, RenderedBox> = {
    let c = NSCache<NSString, RenderedBox>()
    c.countLimit = 2000
    return c
}()

private func renderedSegments(_ raw: String) -> [RenderedSegment] {
    let key = raw as NSString
    if let hit = renderedCache.object(forKey: key) { return hit.segments }
    let out: [RenderedSegment] = parseSegments(raw).compactMap { seg in
        switch seg {
        case .code(let lang, let body):
            return .code(lang: lang, body: body)
        case .text(let s):
            let trimmed = LatexText.render(s.trimmingCharacters(in: .newlines))
            if trimmed.isEmpty { return nil }
            let attr = try? AttributedString(
                markdown: trimmed,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            )
            return .text(attr, plain: trimmed)
        }
    }
    renderedCache.setObject(RenderedBox(out), forKey: key)
    return out
}

// MARK: - Markdown content view

struct MarkdownContentView: View {
    let text: String
    // Thoughts render dimmed (.secondary); replies stay .primary.
    var style: HierarchicalShapeStyle = .primary

    var body: some View {
        let segments = renderedSegments(text)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, seg in
                switch seg {
                case .text(let attr, let plain):
                    if let attr {
                        Text(attr)
                            .foregroundStyle(style)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text(plain)
                            .foregroundStyle(style)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                case .code(let lang, let body):
                    CodeBlockView(lang: lang, code: body)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                    Haptics.tapLight()
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
