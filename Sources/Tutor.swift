import Foundation
import UIKit

enum Tutor {
    enum Provider: String, CaseIterable, Identifiable {
        case openai, anthropic
        var id: String { rawValue }
        var title: String { self == .openai ? "OpenAI" : "Anthropic" }
        var defaultModel: String { self == .openai ? "gpt-5" : "claude-sonnet-5-5" }
    }

    enum Language: String, CaseIterable, Identifiable {
        case english, russian
        var id: String { rawValue }
        var title: String { self == .english ? "English" : "Русский" }
        var voice: String { self == .english ? "en-US" : "ru-RU" }
        var instruction: String {
            self == .english
                ? "Reply in English."
                : "Отвечай по-русски. Числа и формулы пиши словами или простыми цифрами, без LaTeX и markdown, чтобы синтезатор речи мог это прочитать."
        }
    }

    /// The part that gets spoken: the text after the last "ANSWER:" marker, or the whole reply.
    static func spokenPart(of text: String) -> String {
        guard let range = text.range(of: "ANSWER:", options: [.backwards, .caseInsensitive]) else { return text }
        let tail = text[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        return tail.isEmpty ? text : tail
    }

    struct APIError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static let system = """
    You are a math tutor speaking to a student through earbuds. \
    Course context: introductory linear algebra (Lay-style). Questions about invertibility test the \
    Invertible Matrix Theorem. A valid justification is a statement equivalent to invertibility for a square matrix: \
    row equivalent to the identity, a pivot position in every row and column, columns linearly independent, \
    columns span R^n, determinant nonzero, the equation Ax = 0 has only the trivial solution. \
    Superficial properties are distractors and never count as justification, even when the verdict is right: \
    being square, triangular, in echelon form, having no zero entries, having zero entries, not being the identity, \
    not being augmented. \
    Reply in plain English prose only: no markdown, no LaTeX, no bullet symbols. \
    Write every formula in words or simple ASCII so a text-to-speech engine can read it aloud. \
    If the photo is unreadable, say exactly: Photo unreadable, try again.
    """

    static func prompt(for mode: TutorMode, language: Language) -> String {
        let body: String
        switch mode {
        case .check:
            body = """
            The photo shows one or more math problems, on paper or on a screen. Work in this order. \\
            Step 1: look for a pointer: a mouse cursor on a screen, a fingertip, a pen tip, or a highlight. \\
            If a pointer is visible, the target is the single question it points at or is nearest to; ignore the others. \\
            If there is no pointer, the targets are all fully visible questions. \\
            Step 2: transcribe each target question and every one of its answer options exactly as printed, one per line, \\
            including matrix entries. This transcription is for verification. \\
            Step 3: verify by actually computing (determinant, pivots, row reduction), even if the question says \\
            no calculation is needed. \\
            Step 4: for multiple choice, pick the option whose justification is a statement of the Invertible Matrix \\
            Theorem or an equivalent, not a superficial property; the same option texts appear in a different order \\
            under each question, so read each one. \\
            Finish with one final line in exactly this form, always with the question number: ANSWER: 6 E. \\
            Several targets: ANSWER: 5 D, 6 E. If a student's handwritten answer is visible instead: \\
            ANSWER: 6 CORRECT or ANSWER: 6 INCORRECT, followed by at most one short sentence. \\
            Open question: ANSWER: 6 <final value>. Only the ANSWER line is read aloud, so put nothing after it.
            """
        case .solve:
            body = """
            The photo shows a math problem, on paper or on a screen. \
            For a multiple-choice question: say the letter of the correct option, then explain why in one or two sentences, \
            and name the option that students most often pick by mistake. \
            For an open question: solve it in at most four short numbered steps, then state the final answer. \
            If several questions are visible, do this for the first one, then give only the answers for the rest, \
            each prefixed with its number. Stay under 120 words.
            """
        }
        return body + " " + language.instruction
    }

    /// Make sure the model gets a JPEG no wider than 1600 px. The glasses already send a
    /// compressed image; if it is a JPEG and already small enough it goes through untouched.
    static func normalize(_ data: Data) -> Data {
        let isJPEG = data.count > 2 && data[data.startIndex] == 0xFF && data[data.startIndex + 1] == 0xD8
        guard let image = UIImage(data: data) else { return data }
        let maxSide: CGFloat = 1600
        let pixelW = image.size.width * image.scale
        let pixelH = image.size.height * image.scale
        let longest = max(pixelW, pixelH)
        if isJPEG && longest <= maxSide { return data }
        let scale = longest > maxSide ? maxSide / longest : 1
        let size = CGSize(width: (pixelW * scale).rounded(), height: (pixelH * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1   // pixel size == point size; the default would use the screen's 3x
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        return resized.jpegData(compressionQuality: 0.85) ?? data
    }

    static func ask(image: Data, mode: TutorMode, language: Language, provider: Provider, model: String, apiKey: String) async throws -> String {
        let prompt = prompt(for: mode, language: language)
        switch provider {
        case .openai: return try await askOpenAI(image: image, prompt: prompt, model: model, apiKey: apiKey)
        case .anthropic: return try await askAnthropic(image: image, prompt: prompt, model: model, apiKey: apiKey)
        }
    }

    private static func askOpenAI(image: Data, prompt: String, model: String, apiKey: String) async throws -> String {
        var body: [String: Any] = [
            "model": model,
            // Reasoning models (gpt-5 family) spend completion tokens on thinking first;
            // a small budget leaves nothing for the visible answer.
            "max_completion_tokens": 4000,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": [
                    ["type": "text", "text": prompt],
                    ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64," + image.base64EncodedString(), "detail": "high"]],
                ]],
            ],
        ]
        let lower = model.lowercased()
        if lower.hasPrefix("gpt-5") || lower.hasPrefix("o1") || lower.hasPrefix("o3") || lower.hasPrefix("o4") {
            body["reasoning_effort"] = "low"
        }
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let json = try await send(request)
        guard
            let choices = json["choices"] as? [[String: Any]],
            let first = choices.first,
            let message = first["message"] as? [String: Any]
        else { throw APIError(message: "OpenAI: unexpected response") }
        let content = (message["content"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if content.isEmpty {
            let finish = first["finish_reason"] as? String ?? "?"
            let usage = json["usage"] as? [String: Any]
            let details = usage?["completion_tokens_details"] as? [String: Any]
            let reasoning = details?["reasoning_tokens"] as? Int ?? 0
            let refusal = message["refusal"] as? String ?? ""
            throw APIError(message: "OpenAI returned no text (finish_reason=\(finish), reasoning_tokens=\(reasoning)\(refusal.isEmpty ? "" : ", refusal: \(refusal)"))")
        }
        return content
    }

    private static func askAnthropic(image: Data, prompt: String, model: String, apiKey: String) async throws -> String {
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1000,
            "system": system,
            "messages": [
                ["role": "user", "content": [
                    ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": image.base64EncodedString()]],
                    ["type": "text", "text": prompt],
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
        request.timeoutInterval = 180
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
