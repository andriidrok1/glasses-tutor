import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            Form {
                Section("Glasses") {
                    LabeledContent("Registration", value: model.glasses.registration)
                    LabeledContent("Session", value: model.glasses.sessionState)
                    LabeledContent("Shutter", value: model.glasses.shutterReady ? "ready" : "not ready")
                    LabeledContent("Capture button", value: model.glasses.buttonReady ? "listening" : "not attached")
                    Button("1. Register in Meta AI") { Task { await model.glasses.register() } }
                    Button("2. Allow camera in Meta AI") { Task { await model.glasses.requestCameraPermission() } }
                    Button("Reconnect session") { model.glasses.reconnect() }
                }

                Section("Model") {
                    Picker("Provider", selection: $model.provider) {
                        ForEach(Tutor.Provider.allCases) { Text($0.title).tag($0) }
                    }
                    TextField("Model (empty = \(model.provider.defaultModel))", text: $model.model)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("API key", text: $model.apiKey)
                }

                Section("Test without the button") {
                    Button("Capture: check my answer") { model.glasses.capture(mode: .check) }
                    Button("Capture: solve") { model.glasses.capture(mode: .solve) }
                    Button("Say test phrase") { model.speaker.speak("Audio route test. Correct.") }
                }

                Section("Last answer") {
                    if model.busy { ProgressView() }
                    Text(model.lastAnswer.isEmpty ? "—" : model.lastAnswer)
                        .textSelection(.enabled)
                }

                Section("Log") {
                    ForEach(Array(model.glasses.lines.suffix(40).enumerated()), id: \.offset) { _, line in
                        Text(line).font(.system(.caption, design: .monospaced))
                    }
                }
            }
            .navigationTitle("Glasses Tutor")
        }
    }
}
