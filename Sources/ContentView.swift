import MWDATCamera
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            Form {
                Section("Glasses") {
                    LabeledContent("Registration", value: model.glasses.registration)
                    Text(model.glasses.deviceInfo).font(.caption)
                    LabeledContent("Session", value: model.glasses.sessionState)
                    LabeledContent("Shutter", value: model.glasses.shutterReady ? "ready" : "not ready")
                    LabeledContent("Capture button", value: model.glasses.buttonReady ? "listening" : "not attached")
                    Button("1. Register in Meta AI") { Task { await model.glasses.register() } }
                    Button("2. Allow camera in Meta AI") { Task { await model.glasses.requestCameraPermission() } }
                    Button("Reconnect session") { model.glasses.reconnect() }
                    Button("Open glasses firmware update (Meta AI)") { Task { await model.glasses.openFirmwareUpdate() } }
                    Button("Open glasses app update (Meta AI)") { Task { await model.glasses.openGlassesAppUpdate() } }
                }

                Section("Model") {
                    Picker("Provider", selection: $model.provider) {
                        ForEach(Tutor.Provider.allCases) { Text($0.title).tag($0) }
                    }
                    TextField("Model (empty = \(model.provider.defaultModel))", text: $model.model)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("API key", text: $model.apiKey)
                    Picker("Answer language", selection: $model.language) {
                        ForEach(Tutor.Language.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("Photo resolution", selection: $model.photoResolution) {
                        ForEach(PhotoResolution.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    Picker("Photo quality", selection: $model.photoQuality) {
                        ForEach(PhotoQuality.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    Toggle("Speak answer immediately (off = chime, tap to play)", isOn: $model.autoPlay)
                    TextField("Debug server URL (empty = off)", text: $model.debugURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }

                Section("Test without the button") {
                    Button("Capture (single press)") { model.glasses.capture(mode: .check) }
                    Button("Play / pause / repeat (double press)") { model.glasses.log("play: \(model.speaker.togglePause())") }
                    Button("Forget earlier photos (\(model.history.count) remembered)") { model.forgetHistory() }
                        .disabled(model.history.isEmpty)
                    Button("Say test phrase") {
                        model.speaker.speak(model.language == .russian ? "Проверка звука. Верно." : "Audio route test. Correct.", language: model.language.voice)
                    }
                }

                Section("Last photo") {
                    if let photo = model.lastPhoto {
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 260)
                    }
                    Text(model.lastPhotoInfo.isEmpty ? "none yet" : model.lastPhotoInfo).font(.caption)
                }

                Section("Last answer") {
                    if model.busy { ProgressView() }
                    Text(model.lastAnswer.isEmpty ? "—" : model.lastAnswer)
                        .textSelection(.enabled)
                }

                Section("Log (newest first)") {
                    ForEach(Array(model.glasses.lines.suffix(40).reversed().enumerated()), id: \.offset) { _, line in
                        Text(line).font(.system(.caption, design: .monospaced))
                    }
                }
            }
            .navigationTitle("Glasses Tutor")
        }
    }
}
