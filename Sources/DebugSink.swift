import Foundation

/// Mirrors the in-app log, the photos and the model's reply to a tiny HTTP server on the
/// laptop (scripts/debug-server.py) so the developer can watch a session without
/// screenshots. Off when the URL is empty. Fire and forget: a failed post is ignored.
enum DebugSink {
    static var url: URL?

    static func log(_ line: String) {
        post(path: "log", body: Data(line.utf8), type: "text/plain; charset=utf-8")
    }

    static func text(_ name: String, _ text: String) {
        post(path: "text/\(name)", body: Data(text.utf8), type: "text/plain; charset=utf-8")
    }

    static func photo(_ name: String, _ jpeg: Data) {
        post(path: "photo/\(name)", body: jpeg, type: "image/jpeg")
    }

    private static func post(path: String, body: Data, type: String) {
        guard let base = url else { return }
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue(type, forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 5
        URLSession.shared.dataTask(with: request).resume()
    }
}
