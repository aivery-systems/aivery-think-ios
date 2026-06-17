import SwiftUI

// MARK: - Model

enum AgentActionKind {
    case remember, note

    var verb: String { self == .remember ? "remember" : "note" }
    var symbol: String { self == .remember ? "brain.head.profile" : "note.text" }
}

struct AgentAction: Hashable {
    let kind: AgentActionKind
    let detail: String
}

/// An assistant message rendered as an ordered mix of prose and agent-action lines.
enum MessageSegment: Hashable, Identifiable {
    case text(String)
    case action(AgentAction)
    var id: Int { hashValue }
}

// MARK: - Parser

/// Pulls the agent's inline control tags — `<note>…</note>` and `<remember …/>` (or paired
/// `<remember>…</remember>`) — out of a (thinking-stripped) response and returns the prose
/// and actions in the order the model emitted them. Tags we don't surface (validate /
/// get-more-context) and streaming remnants are scrubbed from the prose.
enum AgentActions {
    // 1: note inner · 2: remember self-closing attrs · 3: remember paired attrs · 4: paired inner
    private static let tagRegex = try! NSRegularExpression(
        pattern: #"<\s*note\b[^>]*>([\s\S]*?)<\s*/\s*note\s*>"#
               + #"|<\s*remember\b([^>]*?)/\s*>"#
               + #"|<\s*remember\b([^>]*?)>([\s\S]*?)<\s*/\s*remember\s*>"#,
        options: [.caseInsensitive]
    )
    private static let contentAttr = try! NSRegularExpression(
        pattern: #"content\s*=\s*"([^"]*)""#, options: [.caseInsensitive]
    )

    static func segments(from response: String) -> [MessageSegment] {
        let ns = response as NSString
        var out: [MessageSegment] = []
        var cursor = 0

        for m in tagRegex.matches(in: response, range: NSRange(location: 0, length: ns.length)) {
            if m.range.location > cursor {
                let gap = ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor))
                appendText(cleanProse(gap), to: &out)
            }
            if let action = action(from: m, ns: ns) { out.append(.action(action)) }
            cursor = m.range.location + m.range.length
        }
        if cursor < ns.length {
            appendText(cleanProse(ns.substring(from: cursor)), to: &out)
        }
        return out
    }

    /// Prose only (actions and control tags removed) — for chat history sent back upstream.
    static func plainText(from response: String) -> String {
        segments(from: response)
            .compactMap { if case .text(let t) = $0 { return t } else { return nil } }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Internals

    private static func appendText(_ text: String, to out: inout [MessageSegment]) {
        guard !text.isEmpty else { return }
        out.append(.text(text))
    }

    private static func action(from m: NSTextCheckingResult, ns: NSString) -> AgentAction? {
        func group(_ i: Int) -> String? {
            let r = m.range(at: i)
            return r.location == NSNotFound ? nil : ns.substring(with: r)
        }
        if let noteInner = group(1) {
            let d = oneLine(noteInner)
            return AgentAction(kind: .note, detail: d.isEmpty ? "Noted" : d)
        }
        if let attrs = group(2) {                      // <remember … />
            return AgentAction(kind: .remember, detail: rememberDetail(attrs: attrs, inner: nil))
        }
        if let attrs = group(3) {                      // <remember …>…</remember>
            return AgentAction(kind: .remember, detail: rememberDetail(attrs: attrs, inner: group(4)))
        }
        return nil
    }

    private static func rememberDetail(attrs: String, inner: String?) -> String {
        let ns = attrs as NSString
        if let m = contentAttr.firstMatch(in: attrs, range: NSRange(location: 0, length: ns.length)) {
            let value = oneLine(ns.substring(with: m.range(at: 1)))
            if !value.isEmpty { return value }
        }
        if let inner, case let d = oneLine(inner), !d.isEmpty { return d }
        return "Saved a memory"
    }

    /// Collapse a tag's payload to a single trimmed line (drop nested tags + extra whitespace).
    private static func oneLine(_ s: String) -> String {
        s.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
         .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
         .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Scrub residue from a prose gap: orphaned attribute remnants, leftover validate/
    /// get-more-context tags, and any control tag still streaming in at the end.
    private static func cleanProse(_ text: String) -> String {
        var t = text
        t = t.replacingOccurrences(
            of: #"(?:\s*[A-Za-z_][\w-]*\s*=\s*"[^"]*")+\s*/>"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(
            of: #"<\s*/?\s*(validate|get-more-context)\b[^>]*/?>"#, with: "",
            options: [.regularExpression, .caseInsensitive])
        for pattern in [
            #"<\s*/?\s*(remember|note|validate|get-more-context)\b[\s\S]*$"#,   // unclosed tag at end
            #"(?:\s*[A-Za-z_][\w-]*\s*=\s*"[^"]*")+\s*[A-Za-z_][\w-]*\s*=\s*"[^"]*$"#, // half attr-run
        ] {
            if let r = t.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                t = String(t[t.startIndex..<r.lowerBound])
            }
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Views

/// A single agent action shown like a tool/command line in a terminal:
/// a colored status dot, a monospaced verb, then the detail.
struct AgentActionLineView: View {
    let action: AgentAction

    private var tint: Color { action.kind == .remember ? .accentColor : .secondary }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            Text(action.kind.verb)
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .foregroundStyle(tint)
            Text(action.detail)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(4)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 1)
    }
}

/// Renders an assistant message as ordered prose + action lines. Prose is Markdown when
/// finished; while streaming it's plain text, and the final prose segment carries the caret.
struct AgentMessageContent: View {
    let segments: [MessageSegment]
    var streaming: Bool = false

    private var lastTextIndex: Int? {
        segments.lastIndex { if case .text = $0 { return true } else { return false } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(segments.enumerated()), id: \.offset) { idx, segment in
                switch segment {
                case .text(let text):
                    if streaming {
                        StreamingTextView(text: text, showCaret: idx == lastTextIndex)
                    } else {
                        MarkdownContentView(text: text)
                    }
                case .action(let action):
                    AgentActionLineView(action: action)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Plain streaming text with an optional blinking terminal caret trailing the last glyph.
struct StreamingTextView: View {
    let text: String
    var showCaret: Bool = true

    var body: some View {
        if showCaret {
            TimelineView(.periodic(from: .now, by: 0.6)) { ctx in
                let on = Int(ctx.date.timeIntervalSinceReferenceDate / 0.6) % 2 == 0
                let caret = Text("▍").foregroundStyle(Color.primary.opacity(on ? 0.5 : 0.0))
                Text("\(Text(text))\(caret)")
                    .font(.body)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Text(text)
                .font(.body)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
