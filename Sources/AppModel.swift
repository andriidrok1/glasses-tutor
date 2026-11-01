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
    @Published var lastAnswer = ""
    @Published var busy = false

    let glasses = GlassesController()
    let speaker = Speaker()
    private var pendingMode: TutorMode = .check
    private var cancellables: Set<AnyCancellable> = []

    init() {
        let d = UserDefaults.standard
        provider = Tutor.Provider(rawValue: d.string(forKey: "provider") ?? "") ?? .openai
        model = d.string(forKey: "model") ?? ""
        apiKey = d.string(forKey: "apiKey") ?? ""

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

    func answer(_ raw: Data) async {
        guard !apiKey.isEmpty else {
            lastAnswer = "No API key set."
            speaker.speak("No API key.")
            return
        }
        busy = true
        defer { busy = false }
        let jpeg = Tutor.normalize(raw)
        let effectiveModel = model.isEmpty ? provider.defaultModel : model
        do {
            let text = try await Tutor.ask(
                image: jpeg, mode: pendingMode,
                provider: provider, model: effectiveModel, apiKey: apiKey
            )
            lastAnswer = text
            glasses.log("answer: \(text)")
            speaker.speak(text)
        } catch {
            lastAnswer = "Error: \(error.localizedDescription)"
            glasses.log("api error: \(error)")
            speaker.speak("Request failed.")
        }
    }
}
