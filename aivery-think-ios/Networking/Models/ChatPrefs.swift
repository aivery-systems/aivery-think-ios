import Foundation

// System prompt + chat style, stored locally and sent in each Cortex chat request.
enum ChatPrefsLocal {
    private static let systemPromptKey = "chatSystemPrompt"
    private static let chatStyleKey = "chatStyle"

    static var systemPrompt: String {
        get { UserDefaults.standard.string(forKey: systemPromptKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: systemPromptKey) }
    }

    static var chatStyle: String {
        get { UserDefaults.standard.string(forKey: chatStyleKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: chatStyleKey) }
    }
}

// Style presets mirrored from the web client's FlavorPicker.
struct Flavor: Identifiable, Hashable {
    let id: String
    let name: String
    let prompt: String
}

enum ChatFlavors {
    static let all: [Flavor] = [
        Flavor(id: "professional", name: "Professional", prompt: "Respond in a professional, polished tone. Use formal language and structured responses."),
        Flavor(id: "friendly",     name: "Friendly",     prompt: "Be warm and conversational. Write like a knowledgeable friend."),
        Flavor(id: "technical",    name: "Technical",    prompt: "Use precise technical language. Assume domain expertise. Prefer specificity over simplicity."),
        Flavor(id: "narrative",    name: "Narrative",    prompt: "Frame responses as flowing prose. Prefer story structure over bullet points."),
        Flavor(id: "minimalist",   name: "Minimalist",   prompt: "Be brief. Eliminate filler. Every word must earn its place."),
        Flavor(id: "expressive",   name: "Expressive",   prompt: "Write with energy, personality, and vivid language."),
        Flavor(id: "analytical",   name: "Analytical",   prompt: "Reason explicitly. Break down logic step by step. Favor evidence and tradeoffs."),
        Flavor(id: "playful",      name: "Playful",      prompt: "Be lighthearted and fun. Lean into wit and wordplay where appropriate."),
    ]
}
