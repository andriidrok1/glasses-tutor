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
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        log?("speak: \"\(text.prefix(40))\" via \(route)")
        synthesizer.speak(utterance)
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

    func speechSynthesizer(_ s: AVSpeechSynthesizer, didStart u: AVSpeechUtterance) { log?("speech started") }
    func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) { log?("speech finished") }
    func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel u: AVSpeechUtterance) { log?("speech cancelled") }
    func speechSynthesizer(_ s: AVSpeechSynthesizer, didPause u: AVSpeechUtterance) { log?("speech paused") }
    func speechSynthesizer(_ s: AVSpeechSynthesizer, didContinue u: AVSpeechUtterance) { continued = true; log?("speech continued") }
}
