import Foundation
import UIKit

enum Tutor {
    enum Provider: String, CaseIterable, Identifiable {
        case openai, anthropic
        var id: String { rawValue }
        var title: String { self == .openai ? "OpenAI" : "Anthropic" }
        var defaultModel: String { self == .openai ? "gpt-5" : "claude-sonnet-5-5" }
    }

    struct APIError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static let system = """
    You are a math tutor speaking to a student through earbuds. \
    Reply in plain English prose only: no markdown, no LaTeX, no bullet symbols. \
    Write every formula in words or simple ASCII so a text-to-speech engine can read it aloud. \
    If the photo is unreadable, say exactly: Photo unreadable, try again.
    """

    static func prompt(for mode: TutorMode) -> String {
        switch mode {
        case .check:
            return """
            The photo shows a math problem and the student's handwritten answer. \
            Reply in at most two short sentences. Start with the single word CORRECT or INCORRECT, \
            then one sentence saying why. If no student answer is visible, instead give the final answer in one sentence.
            """
        case .solve:
            return """
            The photo shows a math problem. Solve it in at most four short numbered steps, \
            then state the final answer. Stay under 80 words.
            """
        }
    }

    /// Re-encode whatever the glasses sent (JPEG or HEIC) as a JPEG no wider than 1600 px.
    static func normalize(_ data: Data) -> Data {
        guard let image = UIImage(data: data) else { return data }
        let maxSide: CGFloat = 1600
        let longest = max(image.size.width, image.size.height)
        let scale = longest > maxSide ? maxSide / longest : 1
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        return resized.jpegData(compressionQuality: 0.85) ?? data
    }

    static func ask(image: Data, mode: TutorMode, provider: Provider, model: String, apiKey: String) async throws -> String {
        switch provider {
        case .openai: return try await askOpenAI(image: image, mode: mode, model: model, apiKey: apiKey)
        case .anthropic: return try await askAnthropic(image: image, mode: mode, model: model, apiKey: apiKey)
        }
    }

    private static func askOpenAI(image: Data, mode: TutorMode, model: String, apiKey: String) async throws -> String {
        let body: [String: Any] = [
            "model": model,
            "max_completion_tokens": 400,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": [
                    ["type": "text", "text": prompt(for: mode)],
                    ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64," + image.base64EncodedString()]],
                ]],
            ],
        ]
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let json = try await send(request)
        guard
            let choices = json["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let content = message["content"] as? String
        else { throw APIError(message: "OpenAI: unexpected response") }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func askAnthropic(image: Data, mode: TutorMode, model: String, apiKey: String) async throws -> String {
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 400,
            "system": system,
            "messages": [
                ["role": "user", "content": [
                    ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": image.base64EncodedString()]],
                    ["type": "text", "text": prompt(for: mode)],
                ]],
            ],
        ]
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let json = try await send(request)
        guard
            let content = json["content"] as? [[String: Any]],
            let text = content.first(where: { $0["type"] as? String == "text" })?["text"] as? String
        else { throw APIError(message: "Anthropic: unexpected response") }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func send(_ request: URLRequest) async throws -> [String: Any] {
        var request = request
        request.timeoutInterval = 60
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200..<300).contains(status) else {
            let detail = (json["error"] as? [String: Any])?["message"] as? String
                ?? String(data: data, encoding: .utf8) ?? ""
            throw APIError(message: "HTTP \(status): \(detail.prefix(200))")
        }
        return json
    }
}
