import AVFoundation
import AudioToolbox

/// Speaks through whatever audio output is current. With the glasses connected
/// as the Bluetooth headset that is the glasses' speakers.
final class Speaker: NSObject, AVSpeechSynthesizerDelegate {
    private var synthesizer = AVSpeechSynthesizer()
    private var last: (text: String, language: String)?
    /// An answer that is ready but waits for the double press.
    private var pending: (text: String, language: String)?
    var hasPending: Bool { pending != nil }
    /// Diagnostics go to the app log.
    var log: ((String) -> Void)?
    /// Set by the didContinue callback; a resume that never reports back is restarted.
    private var continued = false
    /// AVSpeechUtterance rate: 0.5 is the system default, lower is slower.
    var rate: Float = 0.42
    private var queued = 0

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    private func activate() {
        let session = AVAudioSession.sharedInstance()
        // .playback ignores the ring/silent switch, so a phone on silent still talks.
        try? session.setCategory(.playback, mode: .spokenAudio, options: [])
        try? session.setActive(true)
    }

    private var route: String {
        AVAudioSession.sharedInstance().currentRoute.outputs
            .map { "\($0.portType.rawValue) \($0.portName)" }
            .joined(separator: ", ")
    }

    func beep() {
        activate()
        AudioServicesPlaySystemSound(1057)
    }

    /// "Answer is ready": a short spoken cue in the glasses plus a buzz of the phone.
    func ready(_ text: String, language: String = "en-US") {
        pending = (text, language)
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        utter("Ready.", language: language)
    }

    func speak(_ text: String, language: String = "en-US") {
        last = (text, language)
        utter(text, language: language)
    }

    private func utter(_ text: String, language: String) {
        activate()
        // A synthesizer left paused swallows new utterances; a stuck one never starts them.
        // Both are cured by throwing it away.
        if synthesizer.isPaused || synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
            synthesizer = AVSpeechSynthesizer()
            synthesizer.delegate = self
        }
        // One utterance per sentence, with a breath between them: time to write a part down.
        let sentences = text
            .replacingOccurrences(of: "; ", with: ". ")
            .components(separatedBy: ". ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let voice = AVSpeechSynthesisVoice(language: language)
        queued = sentences.count
        log?("speak: \"\(text.prefix(40))\" in \(sentences.count) pieces at rate \(rate) via \(route)")
        for sentence in sentences {
            let utterance = AVSpeechUtterance(string: sentence)
            utterance.voice = voice
            utterance.rate = rate
            utterance.postUtteranceDelay = sentences.count > 1 ? 0.9 : 0
            synthesizer.speak(utterance)
        }
    }

    /// Double press: answer waiting → play it, speaking → pause, paused → continue,
    /// silent → repeat the last answer.
    @discardableResult
    func togglePause() -> String {
        if let pending {
            self.pending = nil
            speak(pending.text, language: pending.language)
            return "play"
        }
        if synthesizer.isPaused {
            activate()
            continued = false
            synthesizer.continueSpeaking()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
                guard let self, !self.continued, let last = self.last else { return }
                self.log?("resume did not take, restarting the answer")
                self.speak(last.text, language: last.language)
            }
            return "resume"
        }
        if synthesizer.isSpeaking {
            synthesizer.pauseSpeaking(at: .word)
            return "pause"
        }
        if let last {
            speak(last.text, language: last.language)
            return "repeat"
        }
        return "nothing to play"
    }

    func stop() {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
    }

    // MARK: AVSpeechSynthesizerDelegate

    func speechSynthesizer(_ s: AVSpeechSynthesizer, didStart u: AVSpeechUtterance) {
        if queued > 0 { log?("speech started"); queued = 0 }
    }
    func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) { if !s.isSpeaking { log?("speech finished") } }
    func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) { log?("speech cancelled") }
    func speechSynthesizer(_ s: AVSpeechSynthesizer, didPause u: AVSpeechUtterance) { log?("speech paused") }
    func speechSynthesizer(_ s: AVSpeechSynthesizer, didContinue u: AVSpeechUtterance) { continued = true; log?("speech continued") }
}
