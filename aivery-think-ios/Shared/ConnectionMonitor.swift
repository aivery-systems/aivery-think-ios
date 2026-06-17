import Foundation
import Combine

/// Tracks reachability of the Fabric API for the current host. Pings /api/auth/me,
/// which validates connectivity AND the API key in one request. Networking code can
/// also flip the state immediately via noteOffline()/noteOnline() without waiting
/// for the next poll.
@MainActor
final class ConnectionMonitor: ObservableObject {
    static let shared = ConnectionMonitor()

    enum Status: Equatable {
        case unknown, checking, online, unauthorized, offline

        var label: String {
            switch self {
            case .unknown:      return "—"
            case .checking:     return "Checking…"
            case .online:       return "Connected"
            case .unauthorized: return "Invalid key"
            case .offline:      return "Offline"
            }
        }
    }

    @Published private(set) var status: Status = .unknown
    @Published private(set) var lastChecked: Date?

    private let api = APIClient.shared

    /// Host the memories/conversations API points at (Fabric).
    var host: String { api.baseURL.host ?? api.baseURL.absoluteString }

    func check() async {
        status = .checking
        do {
            try await api.requestEmpty("/api/auth/me", method: "GET")
            status = .online
        } catch APIError.unauthorized {
            status = .unauthorized
        } catch APIError.notFound {
            status = .online   // reachable, endpoint just absent on this backend
        } catch {
            status = .offline
        }
        lastChecked = Date()
    }

    func noteOffline() { status = .offline; lastChecked = Date() }
    func noteOnline()  { if status != .online { status = .online; lastChecked = Date() } }
}
