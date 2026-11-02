import Combine
import Foundation
import UIKit

@MainActor
final class AppModel: ObservableObject {
    @Published var provider: Tutor.Provider {
        didSet { UserDefaults.standard.set(provider.rawValue, forKey: "provider") }
    }
    @Published var model: String {
        didSet { UserDefaults.standard.set(model, forKey: "model") }
    }
    @Published var apiKey: String {
        didSet { UserDefaults.standard.set(apiKey, forKey: "apiKey") }
    }
    @Published var language: Tutor.Language {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: "language") }
    }
    @Published var lastAnswer = ""
    @Published var busy = false
    @Published var lastPhoto: UIImage?
    @Published var lastPhotoInfo = ""

    let glasses = GlassesController()
    let speaker = Speaker()
    private var pendingMode: TutorMode = .check
    private var cancellables: Set<AnyCancellable> = []

    init() {
        let d = UserDefaults.standard
        provider = Tutor.Provider(rawValue: d.string(forKey: "provider") ?? "") ?? .openai
        model = d.string(forKey: "model") ?? ""
        apiKey = d.string(forKey: "apiKey") ?? ""
        language = Tutor.Language(rawValue: d.string(forKey: "language") ?? "") ?? .russian

        // GlassesController is a nested ObservableObject; SwiftUI only watches this one.
        glasses.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        glasses.onCapture = { [weak self] mode in
            self?.pendingMode = mode
            self?.speaker.beep()
        }
        glasses.onPhoto = { [weak self] data in
            Task { await self?.answer(data) }
        }
        glasses.observeRegistration()
        glasses.connect()
    }

    /// Keeps the last few photos in Documents/, visible in the Files app under Glasses Tutor.
    private func savePhoto(_ data: Data) {
        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        try? data.write(to: dir.appendingPathComponent("photo-\(stamp).jpg"))
        if let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for old in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).dropLast(10) {
                try? FileManager.default.removeItem(at: old)
            }
        }
    }

    func answer(_ raw: Data) async {
        guard !apiKey.isEmpty else {
            lastAnswer = "No API key set."
            speaker.speak("No API key.")
            return
        }
        busy = true
        defer { busy = false }
        let jpeg = Tutor.normalize(raw)
        let image = UIImage(data: jpeg)
        lastPhoto = image
        let dims = image.map { "\(Int($0.size.width * $0.scale))x\(Int($0.size.height * $0.scale))" } ?? "undecodable"
        lastPhotoInfo = "raw \(raw.count / 1024) KB → jpeg \(jpeg.count / 1024) KB, \(dims)"
        glasses.log("photo: \(lastPhotoInfo)")
        savePhoto(jpeg)
        let effectiveModel = model.isEmpty ? provider.defaultModel : model
        do {
            let text = try await Tutor.ask(
                image: jpeg, mode: pendingMode, language: language,
                provider: provider, model: effectiveModel, apiKey: apiKey
            )
            lastAnswer = text
            glasses.log("answer: \(text)")
            speaker.speak(text, language: language.voice)
        } catch {
            lastAnswer = "Error: \(error.localizedDescription)"
            glasses.log("api error: \(error)")
            speaker.speak(language == .russian ? "Ошибка запроса." : "Request failed.", language: language.voice)
        }
    }
}
