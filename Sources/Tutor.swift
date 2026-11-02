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
    Spoken format for values: a vector as "v1 = 1, 2, 0" (entries in order, separated by commas); \
    a matrix row by row as "matrix 2 by 3, row 1: 1 2 0, row 2: 2 4 1"; a fraction as "3 over 4"; \
    a power as "x squared" or "x to the 5th"; a root as "square root of 2"; several parts as \
    "part a: ..., part b: ...". \
    The text is often small or photographed at an angle; read it carefully before giving up. \
    Say exactly "Photo unreadable, try again." only when the numbers cannot be made out even in the zoomed image.
    """

    /// Prefix used when the request carries a zoomed crop plus the full frame.
    static let twoImagesNote = """
    You receive two images. Image 1 is a zoomed, full-resolution crop of the text block found in the photo: \
    read the problem from it. Image 2 is the whole photo for context only: use it to see a pointer \
    (cursor, fingertip, pen) and which question it marks. If part of the problem (for example the matrix) \
    is missing from image 1, read it from image 2 and say in the transcription that it came from the \
    small image; if a digit there is ambiguous, say which one.
    """

    static func prompt(for mode: TutorMode, language: Language) -> String {
        let body = """
        The photo shows one or more math problems, on paper or on a screen. Work in this order. \
        Step 1: look for a pointer: a mouse cursor on a screen, a fingertip, a pen tip, or a highlight. \
        If a pointer is visible, the target is the single question, or the single sub-part such as (a) or (b), \
        that it points at or is nearest to; answer only that one and ignore the others. \
        If there is no pointer, the targets are all fully visible questions. \
        Step 2: transcribe the target question and every one of its answer options exactly as printed, one per line, \
        including matrix entries. Then transcribe any work the student has written for it: a circled or marked \
        option, handwritten vectors, matrices, row operations, a final value. Say "student work: none" if there is none. \
        Step 3: verify by actually computing (determinant, pivots, row reduction, matrix-vector products), \
        even if the question says no calculation is needed. \
        Step 4: for multiple choice, pick the option whose justification is a theorem statement or an equivalent, \
        not a superficial property; the same option texts appear in a different order under each question, so read each one. \
        Finish with one final line that starts with ANSWER: and the question number; only that line is read aloud. \
        Rule: if the student wrote nothing for the target, solve it and give the answer: \
        ANSWER: 1 A, or for an open question ANSWER: 1 <final value in the spoken format>. \
        If the student's work is there and right: ANSWER: 1 CORRECT. \
        If it is wrong: ANSWER: 1 INCORRECT, then one short sentence saying exactly where (which part, which entry, \
        which step) and the correct value, for example: ANSWER: 1 INCORRECT. v2 second entry should be 0, not 1. \
        Several targets: ANSWER: 1 A, 2 CORRECT.
        """
        return body + " " + language.instruction
    }

    /// Decodes the photo into an upright, scale-1 UIImage so Vision boxes and crops share one
    /// pixel coordinate system.
    static func upright(_ data: Data) -> UIImage? {
        guard let image = UIImage(data: data) else { return nil }
        let size = CGSize(width: (image.size.width * image.scale).rounded(), height: (image.size.height * image.scale).rounded())
        if image.imageOrientation == .up, image.scale == 1 { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }

    /// JPEG with the longest side clamped to [minSide, maxSide]. Small crops are upscaled on
    /// purpose: vision models read 1200 px of text more reliably than 400 px of it.
    static func jpeg(_ image: UIImage, minSide: CGFloat = 0, maxSide: CGFloat, quality: CGFloat = 0.88) -> Data? {
        let pixelW = image.size.width * image.scale
        let pixelH = image.size.height * image.scale
        let longest = max(pixelW, pixelH)
        var scale: CGFloat = 1
        if longest > maxSide { scale = maxSide / longest } else if longest < minSide { scale = minSide / longest }
        if scale == 1, image.scale == 1, image.imageOrientation == .up { return image.jpegData(compressionQuality: quality) }
        let size = CGSize(width: (pixelW * scale).rounded(), height: (pixelH * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1   // pixel size == point size; the default would use the screen's 3x
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            ctx.cgContext.interpolationQuality = .high
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: quality)
    }

    /// `images`: either [full frame] or [zoomed text crop, full frame].
    static func ask(images: [Data], mode: TutorMode, language: Language, provider: Provider, model: String, apiKey: String) async throws -> String {
        var prompt = prompt(for: mode, language: language)
        if images.count == 2 { prompt = twoImagesNote + " " + prompt }
        switch provider {
        case .openai: return try await askOpenAI(images: images, prompt: prompt, model: model, apiKey: apiKey)
        case .anthropic: return try await askAnthropic(images: images, prompt: prompt, model: model, apiKey: apiKey)
        }
    }

    private static func askOpenAI(images: [Data], prompt: String, model: String, apiKey: String) async throws -> String {
        var parts: [[String: Any]] = [["type": "text", "text": prompt]]
        for image in images {
            parts.append(["type": "image_url", "image_url": ["url": "data:image/jpeg;base64," + image.base64EncodedString(), "detail": "high"]])
        }
        var body: [String: Any] = [
            "model": model,
            // Reasoning models (gpt-5 family) spend completion tokens on thinking first;
            // a small budget leaves nothing for the visible answer.
            "max_completion_tokens": 4000,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": parts],
            ],
        ]
        let lower = model.lowercased()
        if lower.hasPrefix("gpt-5") || lower.hasPrefix("o1") || lower.hasPrefix("o3") || lower.hasPrefix("o4") {
            body["reasoning_effort"] = "medium"
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

    private static func askAnthropic(images: [Data], prompt: String, model: String, apiKey: String) async throws -> String {
        var content: [[String: Any]] = images.map {
            ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": $0.base64EncodedString()]]
        }
        content.append(["type": "text", "text": prompt])
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 1000,
            "system": system,
            "messages": [
                ["role": "user", "content": content],
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
