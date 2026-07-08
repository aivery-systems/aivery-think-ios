import Foundation
import Darwin
import SystemConfiguration

enum APIError: Error {
    case unauthorized
    case rateLimited(reason: String?, resetsAt: String?)
    case notFound
    case serverError(Int)
    case decodingError(Error)
    case networkError(Error)
}

final class APIClient {
    static let shared = APIClient()

    #if DEBUG
    // Resolve local IP for defaults, but still allow env overrides.
    private static func localIPv4Address() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>? = nil
        if getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr {
            defer { freeifaddrs(ifaddr) }
            // First pass: prefer Wi‑Fi (en0) IPv4
            var cursor: UnsafeMutablePointer<ifaddrs>? = firstAddr
            while let ptr = cursor?.pointee {
                let name = String(cString: ptr.ifa_name)
                if name == "en0", ptr.ifa_addr.pointee.sa_family == sa_family_t(AF_INET) {
                    var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(ptr.ifa_addr, socklen_t(ptr.ifa_addr.pointee.sa_len), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
                        address = String(cString: hostname)
                        break
                    }
                }
                cursor = ptr.ifa_next
            }
            // Second pass: any non-loopback IPv4 if en0 not found
            if address == nil {
                cursor = firstAddr
                while let ptr = cursor?.pointee {
                    if ptr.ifa_addr.pointee.sa_family == sa_family_t(AF_INET) {
                        let name = String(cString: ptr.ifa_name)
                        if name != "lo0" {
                            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                            if getnameinfo(ptr.ifa_addr, socklen_t(ptr.ifa_addr.pointee.sa_len), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST) == 0 {
                                address = String(cString: hostname)
                                break
                            }
                        }
                    }
                    cursor = ptr.ifa_next
                }
            }
        }
        return address
    }

    // Persistent in-app host override (Settings → Developer). Survives relaunch
    // with no Xcode tether, so a standalone Debug build can reach the Mac's API
    // over Tailscale from anywhere on the tailnet.
    static let devHostKey = "aivery-dev-host"
    static let defaultDevHost = "christians-macbook-pro.tail2787ff.ts.net"

    /// The override value shown/edited in Settings. Defaults to the Tailscale
    /// MagicDNS name until the user changes it (empty == fall through to auto-detect).
    static var storedDevHost: String {
        (UserDefaults.standard.string(forKey: devHostKey) ?? defaultDevHost)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The host the Debug build talks to. Precedence:
    /// 1. In-app override (defaults to the Tailscale name).
    /// 2. AIVERY_LOCAL_HOST scheme env var (only if the override is cleared).
    /// 3. Auto-detected LAN IPv4.
    private static var localHost: String {
        let stored = storedDevHost
        if !stored.isEmpty { return stored }
        if let raw = ProcessInfo.processInfo.environment["AIVERY_LOCAL_HOST"],
           let token = raw.split(whereSeparator: { $0.isWhitespace }).first {
            return String(token)
        }
        return APIClient.localIPv4Address() ?? "127.0.0.1"
    }

    /// (Re)build the Debug base/cortex URLs from the current host. The full-URL env
    /// overrides AIVERY_BASE_URL / AIVERY_CORTEX_URL still win if set.
    private static func debugURLs() -> (base: URL, cortex: URL) {
        let host = localHost
        let env = ProcessInfo.processInfo.environment
        return (makeURL(env["AIVERY_BASE_URL"] ?? "http://\(host):5128"),
                makeURL(env["AIVERY_CORTEX_URL"] ?? "http://\(host):5127"))
    }
    #endif

    /// Parse a URL string without ever crashing; trims whitespace, falls back to a known-valid literal.
    private static func makeURL(_ string: String) -> URL {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(string: trimmed) ?? URL(string: "http://127.0.0.1:5128")!
    }

    // Fabric API (memories, auth) — override via scheme env var AIVERY_BASE_URL.
    // Cortex (chat agent runtime) — override via AIVERY_CORTEX_URL.
    // Set in init() (not as default values) so referencing our own statics here
    // doesn't create a type-checking cycle with `static let shared`.
    var baseURL: URL
    var cortexURL: URL

    var apiKey: String?
    // Read-only outside APIClient — all writes go through setAgentId(_:) so the
    // Keychain and the Share extension's App Group mirror never drift.
    private(set) var agentId: String = "default"

    private let session = URLSession.shared

    private init() {
        #if DEBUG
        let urls = APIClient.debugURLs()
        baseURL = urls.base
        cortexURL = urls.cortex
        print("🌐 APIClient base=\(baseURL)  cortex=\(cortexURL)")
        #else
        baseURL = URL(string: "https://api.aivery.systems")!
        cortexURL = URL(string: "https://cortex.aivery.systems")!
        #endif
        syncSharedCredentials()
    }

    /// Update the dev host override and re-point base/cortex immediately (Debug only).
    func setDevHost(_ host: String) {
        #if DEBUG
        UserDefaults.standard.set(host.trimmingCharacters(in: .whitespacesAndNewlines),
                                  forKey: APIClient.devHostKey)
        let urls = APIClient.debugURLs()
        baseURL = urls.base
        cortexURL = urls.cortex
        print("🌐 APIClient reconfigured base=\(baseURL)  cortex=\(cortexURL)")
        syncSharedCredentials()
        #endif
    }

    // Mirror credentials into the shared App Group so the Share extension can reach
    // /memory/write with the same key, agent, and host as the app.
    static let sharedAppGroup = "group.matsoukis.aivery-think-ios"
    func syncSharedCredentials() {
        guard let d = UserDefaults(suiteName: APIClient.sharedAppGroup) else { return }
        d.set(apiKey, forKey: "apiKey")
        d.set(agentId, forKey: "agentId")
        d.set(baseURL.absoluteString, forKey: "fabricBaseURL")
    }

    func setApiKey(_ key: String) {
        apiKey = key
        KeychainHelper.save(key: "apiKey", value: key)
        syncSharedCredentials()
    }

    /// Single write path for the agent id: in-memory value, Keychain (so the Siri
    /// intent's restoreApiKey() picks it up), and the App Group mirror for the Share
    /// extension. An empty/whitespace id means "revert to default" — the Keychain
    /// entry is deleted so restoreApiKey() falls back to the initial "default",
    /// instead of persisting an empty X-Agent-Id header forever.
    func setAgentId(_ id: String) {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            agentId = "default"
            KeychainHelper.delete(key: "agentId")
        } else {
            agentId = trimmed
            KeychainHelper.save(key: "agentId", value: trimmed)
        }
        syncSharedCredentials()
    }

    func clearApiKey() {
        apiKey = nil
        KeychainHelper.delete(key: "apiKey")
        syncSharedCredentials()
    }

    func restoreApiKey() -> Bool {
        guard let key = KeychainHelper.load(key: "apiKey") else { return false }
        apiKey = key
        if let savedAgentId = KeychainHelper.load(key: "agentId") {
            agentId = savedAgentId
        }
        syncSharedCredentials()
        return true
    }

    func commonHeaders() -> [String: String] {
        var headers: [String: String] = [
            "Content-Type": "application/json",
            "X-Agent-Id": agentId,
        ]
        if let key = apiKey {
            headers["Authorization"] = "Bearer \(key)"
        }
        return headers
    }

    func request<T: Decodable>(_ path: String, method: String = "GET", body: (any Encodable)? = nil) async throws -> T {
        let url = baseURL.appendingPathComponent(path)
        var req = URLRequest(url: url)
        req.httpMethod = method
        for (k, v) in commonHeaders() { req.setValue(v, forHTTPHeaderField: k) }
        if let body {
            req.httpBody = try JSONEncoder().encode(body)
        }

        #if DEBUG
        print("▶ \(method) \(url)")
        #endif

        let (data, response) = try await session.data(for: req)
        let http = response as! HTTPURLResponse

        #if DEBUG
        let body = String(data: data.prefix(500), encoding: .utf8) ?? "<binary>"
        print("◀ \(http.statusCode) \(method) \(url.path) — \(body)")
        #endif

        switch http.statusCode {
        case 200...299:
            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                throw APIError.decodingError(error)
            }
        case 401:
            throw APIError.unauthorized
        case 404:
            throw APIError.notFound
        case 429:
            let body = (try? JSONDecoder().decode(RateLimitBody.self, from: data))
            throw APIError.rateLimited(reason: body?.reason, resetsAt: body?.resetsAt)
        default:
            throw APIError.serverError(http.statusCode)
        }
    }

    func requestEmpty(_ path: String, method: String, body: (any Encodable)? = nil) async throws {
        let url = baseURL.appendingPathComponent(path)
        var req = URLRequest(url: url)
        req.httpMethod = method
        for (k, v) in commonHeaders() { req.setValue(v, forHTTPHeaderField: k) }
        if let body {
            req.httpBody = try JSONEncoder().encode(body)
        }
        let (_, response) = try await session.data(for: req)
        let http = response as! HTTPURLResponse
        switch http.statusCode {
        case 200...299: return
        case 401: throw APIError.unauthorized
        case 404: throw APIError.notFound
        default: throw APIError.serverError(http.statusCode)
        }
    }

    // Direct capture: store a memory via the Fabric protocol write endpoint
    // (embeds + persists server-side). Used by the Remember intent / share sheet.
    // Short timeout so the Siri intent fails fast instead of hanging past its budget.
    func writeMemory(content: String, type: String = "semantic", source: String) async throws {
        struct Body: Encodable {
            let content: String
            let agent_id: String
            let type: String
            let source: String
            let confidence: Double
        }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        var req = URLRequest(url: baseURL.appendingPathComponent("/memory/write"), timeoutInterval: 12)
        req.httpMethod = "POST"
        for (k, v) in commonHeaders() { req.setValue(v, forHTTPHeaderField: k) }
        req.httpBody = try JSONEncoder().encode(
            Body(content: trimmed, agent_id: agentId, type: type, source: source, confidence: 1.0))

        let (_, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.networkError(URLError(.badServerResponse))
        }
        switch http.statusCode {
        case 200...299: return
        case 401:       throw APIError.unauthorized
        default:        throw APIError.serverError(http.statusCode)
        }
    }

    private struct RateLimitBody: Decodable {
        let reason: String?
        let resetsAt: String?
    }
}

