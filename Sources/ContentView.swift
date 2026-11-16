import MWDATCamera
import MWDATCore
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showAdvanced = false

    private var registered: Bool { model.glasses.registrationState == .registered }
    private var setupDone: Bool {
        registered && model.glasses.cameraAllowed == true && !model.apiKey.isEmpty && model.consent
    }

    var body: some View {
        NavigationStack {
            Form {
                if !setupDone { setupSection }

                Section("Status") {
                    LabeledContent("Glasses", value: model.glasses.sessionState)
                    LabeledContent("Shutter", value: model.glasses.shutterReady ? "ready" : "not ready")
                    LabeledContent("Capture button", value: model.glasses.buttonReady ? "listening" : "not attached")
                    Button("Reconnect glasses") { model.glasses.reconnect() }
                    if setupDone {
                        Text("Press the capture button on the glasses: one press takes a photo of the problem, a double press plays, pauses or repeats the answer.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Answer") {
                    Picker("Language", selection: $model.language) {
                        ForEach(Tutor.Language.allCases) { Text($0.title).tag($0) }
                    }
                    HStack {
                        Text("Speech rate")
                        Slider(value: $model.speechRate, in: 0.3...0.55)
                        Text(String(format: "%.2f", model.speechRate)).font(.caption).monospacedDigit()
                    }
                    Toggle("Speak answer immediately (off = chime, double press to play)", isOn: $model.autoPlay)
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

                Section {
                    DisclosureGroup("Advanced", isExpanded: $showAdvanced) { advanced }
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

    // MARK: - First run

    @ViewBuilder private var setupSection: some View {
        Section {
            step(1, done: registered, title: "Developer Mode on the glasses") {
                Text("Meta AI app → Settings → App Info → tap the version number 5 times → turn on Developer Mode.")
            }
            step(2, done: registered, title: "Connect this app in Meta AI") {
                Button("Open Meta AI to connect") { Task { await model.glasses.register() } }
            }
            step(3, done: model.glasses.cameraAllowed == true, title: "Allow the glasses camera") {
                Button("Open Meta AI, choose Allow always") { Task { await model.glasses.requestCameraPermission() } }
                    .disabled(!registered)
            }
            step(4, done: !model.apiKey.isEmpty, title: "Your AI key") {
                Picker("Provider", selection: $model.provider) {
                    ForEach(Tutor.Provider.allCases) { Text($0.title).tag($0) }
                }
                SecureField(model.provider == .openai ? "sk-..." : "sk-ant-...", text: $model.apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Link("Get a key", destination: URL(string: model.provider == .openai
                    ? "https://platform.openai.com/api-keys"
                    : "https://console.anthropic.com/settings/keys")!)
                Text("The key stays in this phone's Keychain. Requests are billed to your account, about 1 to 3 cents per photo.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            step(5, done: model.consent, title: "Sending photos") {
                Text("Each photo you take with the capture button is sent to \(model.provider.title) with your key to get the answer. Glasses Tutor has no server and keeps nothing besides the last few photos on this phone.")
                    .font(.caption)
                Toggle("I agree", isOn: $model.consent)
                Link("Privacy policy", destination: URL(string: "https://github.com/andriidrok1/glasses-tutor/blob/main/PRIVACY.md")!)
                    .font(.caption)
            }
        } header: {
            Text("Setup")
        } footer: {
            Text("Works with Ray-Ban Meta glasses paired in the Meta AI app.")
        }
    }

    @ViewBuilder
    private func step<Content: View>(_ n: Int, done: Bool, title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("\(n). \(title)", systemImage: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? .green : .primary)
                .font(.headline)
            if !done { content() }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Advanced

    @ViewBuilder private var advanced: some View {
        LabeledContent("Registration", value: model.glasses.registration)
        Text(model.glasses.deviceInfo).font(.caption)
        if setupDone {
            Picker("Provider", selection: $model.provider) {
                ForEach(Tutor.Provider.allCases) { Text($0.title).tag($0) }
            }
            SecureField("API key", text: $model.apiKey)
            Toggle("Send photos to the AI provider", isOn: $model.consent)
        }
        TextField("Model (empty = \(model.provider.defaultModel))", text: $model.model)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        Picker("Photo resolution", selection: $model.photoResolution) {
            ForEach(PhotoResolution.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        Picker("Photo quality", selection: $model.photoQuality) {
            ForEach(PhotoQuality.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }
        Picker("Image sent", selection: $model.imageMode) {
            ForEach(AppModel.ImageMode.allCases) { Text($0.title).tag($0) }
        }
        TextField("Debug server URL (empty = off)", text: $model.debugURL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.URL)
        Button("Open glasses firmware update (Meta AI)") { Task { await model.glasses.openFirmwareUpdate() } }
        Button("Open glasses app update (Meta AI)") { Task { await model.glasses.openGlassesAppUpdate() } }
    }
}
