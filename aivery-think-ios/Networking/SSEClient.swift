import Foundation

final class SSEClient: NSObject {
    private var task: URLSessionDataTask?
    private var urlSession: URLSession?
    private var buffer = ""
    private var cancelled = false

    var onEvent: ((SSEEvent) -> Void)?
    var onComplete: (() -> Void)?
    var onHTTPError: ((Int, String) -> Void)?  // (statusCode, body)

    func connect(with request: URLRequest) {
        cancelled = false
        buffer = ""

        // Tear down any prior session — URLSession retains its delegate until invalidated,
        // so reusing/leaking sessions accumulates memory across messages.
        urlSession?.invalidateAndCancel()
        urlSession = nil

        var req = request
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        req.setValue("no-cache", forHTTPHeaderField: "Cache-Control")

        let config = URLSessionConfiguration.default
        // 0 = "use default" (60s) in URLSession — NOT infinite. Use large values instead.
        config.timeoutIntervalForRequest = 300   // 5 min between data packets (LLM inference gap)
        config.timeoutIntervalForResource = 1800 // 30 min total stream lifetime
        let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        urlSession = session
        task = session.dataTask(with: req)
        task?.resume()
    }

    func cancel() {
        cancelled = true
        task?.cancel()
        urlSession?.invalidateAndCancel()
        urlSession = nil
    }

    deinit {
        urlSession?.invalidateAndCancel()
    }

    // MARK: - Parsing

    private func parseBlock(_ block: String) -> (eventName: String, data: String)? {
        var eventName = "message"
        var dataLines: [String] = []

        for line in block.components(separatedBy: "\n") {
            if line.isEmpty || line.hasPrefix(":") { continue }
            if line.hasPrefix("event:") {
                let v = line.dropFirst(6).trimmingCharacters(in: .whitespaces)
                if !v.isEmpty { eventName = v }
            } else if line.hasPrefix("data:") {
                let raw = String(line.dropFirst(5))
                dataLines.append(raw.hasPrefix(" ") ? String(raw.dropFirst()) : raw)
            }
        }
        guard !dataLines.isEmpty else { return nil }
        return (eventName, dataLines.joined(separator: "\n"))
    }

    private func dispatchEvent(name: String, data: String) {
        switch name {
        case "chunk":
            let text = (try? JSONDecoder().decode(String.self, from: Data(data.utf8))) ?? data
            onEvent?(.chunk(text))

        case "think_chunk":
            let text = (try? JSONDecoder().decode(String.self, from: Data(data.utf8))) ?? data
            onEvent?(.thinkChunk(text))

        case "memory_retrieval_stage":
            if let stage = try? JSONDecoder().decode(RetrievalStageEvent.self, from: Data(data.utf8)) {
                onEvent?(.retrievalStage(stage))
            }

        case "memory_retrieval_result", "session_memory_context":
            if let mems = try? JSONDecoder().decode([RetrievedMemory].self, from: Data(data.utf8)) {
                onEvent?(.memoryResult(mems))
            }

        case "memory_written":
            onEvent?(.memoryWritten)

        case "done":
            onEvent?(.done)

        case "error":
            onEvent?(.error)

        default:
            break // job_created and other pipeline events are silently ignored
        }
    }
}

extension SSEClient: URLSessionDataDelegate {
    // Check HTTP status before reading the body
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask,
                    didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let http = response as? HTTPURLResponse else {
            completionHandler(.allow); return
        }
        if http.statusCode == 200 {
            completionHandler(.allow)
        } else {
            // Cancel and let didCompleteWithError fire; read error body via separate request if needed
            DispatchQueue.main.async { [weak self] in
                self?.onHTTPError?(http.statusCode, HTTPURLResponse.localizedString(forStatusCode: http.statusCode))
            }
            completionHandler(.cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let chunk = String(data: data, encoding: .utf8) else { return }
        #if DEBUG
        print("SSE raw: \(chunk.prefix(200))")
        #endif
        buffer += chunk

        while true {
            guard let sepRange = buffer.range(of: "\n\n") ?? buffer.range(of: "\r\n\r\n") else { break }
            let block = String(buffer[buffer.startIndex..<sepRange.lowerBound])
            buffer = String(buffer[sepRange.upperBound...])
            guard let parsed = parseBlock(block) else { continue }
            DispatchQueue.main.async { [weak self] in
                self?.dispatchEvent(name: parsed.eventName, data: parsed.data)
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let nsErr = error as NSError?
        let isRealError = nsErr != nil && !cancelled && nsErr!.code != NSURLErrorCancelled

        DispatchQueue.main.async { [weak self] in
            if isRealError {
                // Surface connection errors as HTTP-style error so ChatViewModel shows them
                self?.onHTTPError?(nsErr!.code, nsErr!.localizedDescription)
            } else {
                self?.onComplete?()
            }
        }

        // Always release the session (and its strong ref to this delegate) once the
        // stream ends — otherwise every message leaks a URLSession until OOM.
        session.finishTasksAndInvalidate()
        urlSession = nil
    }
}
