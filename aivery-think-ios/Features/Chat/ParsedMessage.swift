import Foundation

/// Everything a finished message bubble renders, parsed once from its raw content.
///
/// A stored message's content is immutable, but SwiftUI re-runs a bubble's body for
/// every parent invalidation (each keystroke in the composer used to re-render every
/// bubble). The parse chain — agent notes, memory refs, think split, agent-action
/// regexes — ran about four times per bubble per render. Caching by content makes a
/// re-render a dictionary lookup.
struct ParsedMessage {
    let thinking: String?
    let actions: [AgentAction]
    let prose: String
    /// Response text without reasoning or persisted blocks — what "Copy" puts on the pasteboard.
    let copyText: String
    let notes: [String]
    let refs: [WrittenMemoryRef]

    static func parse(_ content: String) -> ParsedMessage {
        let notesExtract = AgentNotes.extract(from: content)
        let refsExtract = MemoryRefs.extract(from: notesExtract.content)
        let split = ThinkText.split(refsExtract.content)
        let segments = AgentActions.segments(from: split.response)
        let actions = segments.compactMap { seg -> AgentAction? in
            if case .action(let a) = seg { return a } else { return nil }
        }
        let prose = segments
            .compactMap { seg -> String? in if case .text(let t) = seg { return t } else { return nil } }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return ParsedMessage(
            thinking: split.thinking.isEmpty ? nil : split.thinking,
            actions: actions,
            prose: prose,
            copyText: split.response,
            notes: notesExtract.notes,
            refs: refsExtract.refs
        )
    }

    private final class Box { let value: ParsedMessage; init(_ v: ParsedMessage) { value = v } }
    private static let cache: NSCache<NSString, Box> = {
        let c = NSCache<NSString, Box>()
        c.countLimit = 2000
        return c
    }()

    /// Cached parse, keyed by the full content (identical content → identical parse).
    static func cached(_ content: String) -> ParsedMessage {
        let key = content as NSString
        if let hit = cache.object(forKey: key) { return hit.value }
        let parsed = parse(content)
        cache.setObject(Box(parsed), forKey: key)
        return parsed
    }
}
