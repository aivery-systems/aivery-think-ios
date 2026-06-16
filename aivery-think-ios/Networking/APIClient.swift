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

    private static var localHost: String {
        // Take the first whitespace/newline-delimited token, so a mangled env-var
        // value (stray spaces, duplicated lines) can't corrupt the URL.
        if let raw = ProcessInfo.processInfo.environment["AIVERY_LOCAL_HOST"],
           let token = raw.split(whereSeparator: { $0.isWhitespace }).first {
            return String(token)
        }
        return APIClient.localIPv4Address() ?? "127.0.0.1"
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
    var agentId: String = "default"

    private let session = URLSession.shared

    private init() {
        #if DEBUG
        let host = APIClient.localHost
        let env = ProcessInfo.processInfo.environment
        baseURL = APIClient.makeURL(env["AIVERY_BASE_URL"] ?? "http://\(host):5128")
        cortexURL = APIClient.makeURL(env["AIVERY_CORTEX_URL"] ?? "http://\(host):5127")
        print("🌐 APIClient host=\(host)  base=\(baseURL)  cortex=\(cortexURL)")
        #else
        baseURL = URL(string: "https://api.aivery.systems")!
        cortexURL = URL(string: "https://cortex.aivery.systems")!
        #endif
    }

    func setApiKey(_ key: String) {
        apiKey = key
        KeychainHelper.save(key: "apiKey", value: key)
    }

    func clearApiKey() {
        apiKey = nil
        KeychainHelper.delete(key: "apiKey")
    }

    func restoreApiKey() -> Bool {
        guard let key = KeychainHelper.load(key: "apiKey") else { return false }
        apiKey = key
        if let savedAgentId = KeychainHelper.load(key: "agentId") {
            agentId = savedAgentId
        }
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

    private struct RateLimitBody: Decodable {
        let reason: String?
        let resetsAt: String?
    }
}

