import Foundation

/// Memories written during a turn, persisted inside the assistant message as a trailing
/// `<memory_refs>[…json…]</memory_refs>` block — mirroring the web client
/// (aivery-think/.../chat/chat-history.tsx) so "Memory saved" chips survive reload.
/// Cortex appends the same block when logging the turn to Fabric, so history synced
/// from the server carries it too.
enum MemoryRefs {
    private static let pattern = #"\n?<memory_refs>([\s\S]*?)</memory_refs>"#

    /// Append refs to message content for persistence. No-op when refs is empty.
    static func embed(_ refs: [WrittenMemoryRef], into content: String) -> String {
        guard !refs.isEmpty,
              let data = try? JSONEncoder().encode(refs),
              let json = String(data: data, encoding: .utf8) else { return content }
        return "\(content)\n<memory_refs>\(json)</memory_refs>"
    }

    /// Pull refs out of message content and return the cleaned content without the tag.
    static func extract(from content: String) -> (refs: [WrittenMemoryRef], content: String) {
        guard let range = content.range(of: pattern, options: .regularExpression) else {
            return ([], content)
        }
        let inner = content.range(of: #"<memory_refs>([\s\S]*?)</memory_refs>"#, options: .regularExpression)
            .map { String(content[$0]) } ?? ""
        let jsonStr = inner
            .replacingOccurrences(of: "<memory_refs>", with: "")
            .replacingOccurrences(of: "</memory_refs>", with: "")
        let cleaned = content.replacingCharacters(in: range, with: "")
        let refs = (try? JSONDecoder().decode([WrittenMemoryRef].self, from: Data(jsonStr.utf8))) ?? []
        return (refs, cleaned)
    }
}
