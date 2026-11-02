import AVFoundation
import AudioToolbox

/// Speaks through whatever audio output is current. With the glasses connected
/// as the Bluetooth headset that is the glasses' speakers.
final class Speaker: NSObject {
    private let synthesizer = AVSpeechSynthesizer()
    private var last: (text: String, language: String)?
    /// An answer that is ready but waits for a tap on the touchpad.
    private var pending: (text: String, language: String)?
    var hasPending: Bool { pending != nil }

    private func activate() {
        let session = AVAudioSession.sharedInstance()
        // .playback ignores the ring/silent switch, so a phone on silent still talks.
        try? session.setCategory(.playback, mode: .spokenAudio, options: [])
        try? session.setActive(true)
    }

    func beep() {
        activate()
        AudioServicesPlaySystemSound(1057)
    }

    /// "Answer is ready": a different short sound in the glasses plus a buzz of the phone.
    func ready(_ text: String, language: String = "en-US") {
        activate()
        pending = (text, language)
        AudioServicesPlaySystemSound(1003)
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
    }

    func speak(_ text: String, language: String = "en-US") {
        activate()
        last = (text, language)
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }

    /// Double press: answer waiting → play it, speaking → pause, paused → continue,
    /// silent → repeat the last answer.
    /// Returns a word for the log.
    @discardableResult
    func togglePause() -> String {
        if let pending {
            self.pending = nil
            speak(pending.text, language: pending.language)
            return "play"
        }
        if synthesizer.isPaused {
            synthesizer.continueSpeaking()
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
}
