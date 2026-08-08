import UIKit
import Social
import UniformTypeIdentifiers

/// "Share → Aivery": a compose sheet that saves the shared text/URL as a memory via the
/// Fabric /memory/write endpoint. Credentials come from the App Group the main app mirrors.
class ShareViewController: SLComposeServiceViewController {

    private let appGroup = "group.systems.aivery.think"

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Aivery"
        placeholder = "Save to Aivery…"
    }

    override func presentationAnimationDidFinish() {
        loadSharedItem { [weak self] text in
            guard let self, let text, !text.isEmpty else { return }
            DispatchQueue.main.async {
                if (self.contentText ?? "").isEmpty {
                    self.textView.text = text
                    self.validateContent()
                }
            }
        }
    }

    override func isContentValid() -> Bool {
        !(contentText ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    override func didSelectPost() {
        let content = (contentText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { complete(); return }
        saveMemory(content) { [weak self] in self?.complete() }
    }

    override func configurationItems() -> [Any]! { [] }

    // MARK: - Helpers

    private func complete() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }

    /// Pull plain text, then a URL, out of the share payload.
    private func loadSharedItem(_ done: @escaping (String?) -> Void) {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let providers = item.attachments, !providers.isEmpty else { done(nil); return }

        let textType = UTType.plainText.identifier
        let urlType = UTType.url.identifier
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(textType) {
                provider.loadItem(forTypeIdentifier: textType, options: nil) { obj, _ in
                    done(obj as? String)
                }
                return
            }
            if provider.hasItemConformingToTypeIdentifier(urlType) {
                provider.loadItem(forTypeIdentifier: urlType, options: nil) { obj, _ in
                    done((obj as? URL)?.absoluteString)
                }
                return
            }
        }
        done(nil)
    }

    /// POST the memory; the completion fires after the request finishes so the extension
    /// isn't torn down mid-flight.
    private func saveMemory(_ content: String, completion: @escaping () -> Void) {
        let defaults = UserDefaults(suiteName: appGroup)
        guard let key = defaults?.string(forKey: "apiKey"), !key.isEmpty else { completion(); return }
        let agentId = defaults?.string(forKey: "agentId") ?? "default"
        let base = defaults?.string(forKey: "fabricBaseURL") ?? "https://api.aivery.systems"
        let endpoint = base.hasSuffix("/") ? base + "memory/write" : base + "/memory/write"
        guard let url = URL(string: endpoint) else { completion(); return }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue(agentId, forHTTPHeaderField: "X-Agent-Id")
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "content": content,
            "agent_id": agentId,
            "type": "semantic",
            "source": "ios-share",
            "confidence": 1.0,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
        ])

        URLSession.shared.dataTask(with: req) { _, _, _ in
            DispatchQueue.main.async { completion() }
        }.resume()
    }
}
