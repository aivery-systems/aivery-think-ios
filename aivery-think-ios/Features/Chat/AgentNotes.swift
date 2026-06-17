import Foundation

/// Agent action notes ("Stored a memory about …") that the model emits via <note> tags.
/// Cortex surfaces them as `agent_note` SSE events; we persist them inside the assistant
/// message as a trailing `<agent_notes>[…json…]</agent_notes>` block — mirroring the web
/// client (aivery-think/.../chat/chat-history.tsx) so the chip survives reload.
enum AgentNotes {
    private static let pattern = #"\n?<agent_notes>([\s\S]*?)</agent_notes>"#

    /// Append notes to message content for persistence. No-op when notes is empty.
    static func embed(_ notes: [String], into content: String) -> String {
        guard !notes.isEmpty,
              let data = try? JSONEncoder().encode(notes),
              let json = String(data: data, encoding: .utf8) else { return content }
        return "\(content)\n<agent_notes>\(json)</agent_notes>"
    }

    /// Pull notes out of message content and return the cleaned content without the tag.
    static func extract(from content: String) -> (notes: [String], content: String) {
        guard let range = content.range(of: pattern, options: .regularExpression) else {
            return ([], content)
        }
        let inner = content.range(of: #"<agent_notes>([\s\S]*?)</agent_notes>"#, options: .regularExpression)
            .map { String(content[$0]) } ?? ""
        let jsonStr = inner
            .replacingOccurrences(of: "<agent_notes>", with: "")
            .replacingOccurrences(of: "</agent_notes>", with: "")
        let cleaned = content.replacingCharacters(in: range, with: "")
        let notes = (try? JSONDecoder().decode([String].self, from: Data(jsonStr.utf8))) ?? []
        return (notes, cleaned)
    }
}
