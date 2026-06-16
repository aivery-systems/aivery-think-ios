import Foundation

struct ProviderSettings: Codable {
    var enabled: Bool
    var type: String        // "ollama" | "openai"
    var baseUrl: String
    var apiKey: String?
    var model: String

    init(enabled: Bool = false, type: String = "ollama", baseUrl: String = "", apiKey: String? = nil, model: String = "") {
        self.enabled = enabled
        self.type = type
        self.baseUrl = baseUrl
        self.apiKey = apiKey
        self.model = model
    }
}

struct VerifyResponse: Decodable {
    let models: [String]
}

// Provider settings are stored locally and sent in each Cortex chat request.
enum ProviderSettingsLocal {
    private static let key = "providerSettings"

    static func load() -> ProviderSettings? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(ProviderSettings.self, from: data)
    }

    static func save(_ settings: ProviderSettings) {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }
}
