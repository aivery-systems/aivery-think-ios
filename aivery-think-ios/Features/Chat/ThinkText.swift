import Foundation

/// Splits assistant text into reasoning (`<think>`/`<thinking>` blocks) and the visible
/// response. Mirrors the web client's `splitThinking` (aivery-think/.../chat/think-text.ts).
///
/// Handles, in order: any number of well-formed blocks, an unclosed block (rest is
/// reasoning), a bare closing tag used as a reasoning/answer divider, and stray leftover
/// tags — without ever deleting the start of a real answer.
enum ThinkText {
    static func split(_ text: String) -> (thinking: String, response: String) {
        var thinking = ""
        var response = ""
        var remaining = Substring(text)

        // Reasoning tag pairs, in the order models commonly use them.
        let tagPairs = [
            (open: "<think>",     close: "</think>"),
            (open: "<thinking>",  close: "</thinking>"),
            (open: "<reasoning>", close: "</reasoning>"),
        ]

        while !remaining.isEmpty {
            // Match whichever open tag comes first.
            var match: (openRange: Range<Substring.Index>, close: String)?
            for pair in tagPairs {
                guard let r = remaining.range(of: pair.open) else { continue }
                if match == nil || r.lowerBound < match!.openRange.lowerBound {
                    match = (r, pair.close)
                }
            }
            guard let match else {
                response += remaining
                remaining = Substring()
                continue
            }

            response += remaining[remaining.startIndex..<match.openRange.lowerBound]
            remaining = remaining[match.openRange.upperBound...]

            guard let closeRange = remaining.range(of: match.close) else {
                thinking += remaining // unclosed — rest is reasoning
                remaining = Substring()
                continue
            }
            thinking += remaining[remaining.startIndex..<closeRange.lowerBound]
            remaining = remaining[closeRange.upperBound...]
        }

        // A bare closing tag with no opener is some models' reasoning/answer divider:
        // text before it is reasoning. Only when no well-formed block was parsed above —
        // otherwise a stray close tag inside a real answer would delete the reply's start.
        if thinking.isEmpty {
            let bare = ["</think>", "</thinking>", "</reasoning>"]
                .compactMap { response.range(of: $0) }
                .min(by: { $0.lowerBound < $1.lowerBound })
            if let bare {
                thinking = String(response[response.startIndex..<bare.lowerBound])
                response = String(response[bare.upperBound...])
            }
        }

        // Drop any leftover stray tags in place, keeping the surrounding text intact.
        for tag in ["<think>", "</think>", "<thinking>", "</thinking>", "<reasoning>", "</reasoning>"] {
            response = response.replacingOccurrences(of: tag, with: "")
        }

        // Strip the control tags we DON'T surface to the user (<validate …/>,
        // <get-more-context …/>). <remember …/> and <note>…</note> are intentionally
        // PRESERVED here so AgentActions can render them as inline action lines — it also
        // handles their orphaned/streaming remnants. Done before markdown rendering.
        response = response.replacingOccurrences(
            of: #"<\s*/?\s*(validate|get-more-context)\b[^>]*/?>"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )

        // A validate/get-more-context tag still arriving (unclosed) at the very end while
        // streaming — trim it so the half-typed tag never flashes in the reply.
        if let partial = response.range(
            of: #"<\s*/?\s*(validate|get-more-context)\b[^>]*$"#,
            options: [.regularExpression, .caseInsensitive]
        ) {
            response = String(response[response.startIndex..<partial.lowerBound])
        }

        return (
            thinking.trimmingCharacters(in: .whitespacesAndNewlines),
            response.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}
