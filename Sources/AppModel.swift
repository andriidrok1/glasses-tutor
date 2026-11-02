import Combine
import Foundation
import MWDATCamera
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
    @Published var photoResolution: PhotoResolution {
        didSet { UserDefaults.standard.set(photoResolution.rawValue, forKey: "photoResolution"); glasses.photoResolution = photoResolution }
    }
    @Published var photoQuality: PhotoQuality {
        didSet { UserDefaults.standard.set(photoQuality.rawValue, forKey: "photoQuality"); glasses.photoQuality = photoQuality }
    }
    /// Empty = speak the answer as soon as it arrives; otherwise chime and wait for a touchpad tap.
    @Published var autoPlay: Bool {
        didSet { UserDefaults.standard.set(autoPlay, forKey: "autoPlay") }
    }
    @Published var debugURL: String {
        didSet { UserDefaults.standard.set(debugURL, forKey: "debugURL"); DebugSink.url = URL(string: debugURL) }
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
        language = Tutor.Language(rawValue: d.string(forKey: "language") ?? "") ?? .english
        photoResolution = PhotoResolution(rawValue: d.string(forKey: "photoResolution") ?? "") ?? .full
        photoQuality = PhotoQuality(rawValue: d.string(forKey: "photoQuality") ?? "") ?? .medium
        autoPlay = d.object(forKey: "autoPlay") as? Bool ?? false
        debugURL = d.string(forKey: "debugURL") ?? ""
        glasses.photoResolution = photoResolution
        glasses.photoQuality = photoQuality
        DebugSink.url = URL(string: debugURL)

        // GlassesController is a nested ObservableObject; SwiftUI only watches this one.
        glasses.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)

        glasses.onCapture = { [weak self] mode in
            self?.pendingMode = mode
            self?.speaker.beep()
        }
        glasses.onPlay = { [weak self] in
            guard let self else { return }
            glasses.log("play: \(speaker.togglePause())")
        }
        glasses.onPhoto = { [weak self] data in
            Task { await self?.answer(data) }
        }
        glasses.observeRegistration()
        glasses.connect()
    }

    /// Keeps the last few photos in Documents/, visible in the Files app under Glasses Tutor.
    private func savePhoto(_ data: Data, suffix: String = "") {
        guard let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        try? data.write(to: dir.appendingPathComponent("photo-\(stamp)\(suffix).jpg"))
        if let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for old in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).dropLast(20) {
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
        guard let upright = Tutor.upright(raw) else {
            lastAnswer = "Photo could not be decoded (\(raw.count) bytes)."
            glasses.log(lastAnswer)
            return
        }
        let rawDims = "\(Int(upright.size.width))x\(Int(upright.size.height))"
        // Full frame for context (pointer, which question), zoomed text block for reading.
        let full = Tutor.jpeg(upright, maxSide: 1600, quality: 0.8) ?? raw
        var images = [full]
        var info = "raw \(raw.count / 1024) KB \(rawDims) → full \(full.count / 1024) KB"
        let match = await Task.detached(priority: .userInitiated) { TextRegion.find(in: upright) }.value
        if let match, let zoom = Tutor.jpeg(match.crop, minSide: 1400, maxSide: 2000) {
            images.insert(zoom, at: 0)
            lastPhoto = match.crop
            DebugSink.photo("zoom", zoom)
            info += "; text block \(match.lines) lines \(Int(match.rect.width))x\(Int(match.rect.height)) → zoom \(zoom.count / 1024) KB"
            savePhoto(zoom, suffix: "-zoom")
        } else {
            lastPhoto = upright
            info += "; no text block found, sending full frame"
        }
        lastPhotoInfo = info
        glasses.log("photo: \(info)")
        savePhoto(full)
        DebugSink.photo("full", full)
        let effectiveModel = model.isEmpty ? provider.defaultModel : model
        do {
            let text = try await Tutor.ask(
                images: images, mode: pendingMode, language: language,
                provider: provider, model: effectiveModel, apiKey: apiKey
            )
            lastAnswer = text
            DebugSink.text("reply", text)
            let spoken = Tutor.spokenPart(of: text)
            if autoPlay {
                glasses.log("answer: \(spoken)")
                speaker.speak(spoken, language: language.voice)
            } else {
                glasses.log("answer ready, tap to play: \(spoken)")
                speaker.ready(spoken, language: language.voice)
            }
        } catch {
            lastAnswer = "Error: \(error.localizedDescription)"
            glasses.log("api error: \(error)")
            speaker.speak(language == .russian ? "Ошибка запроса." : "Request failed.", language: language.voice)
        }
    }
}
