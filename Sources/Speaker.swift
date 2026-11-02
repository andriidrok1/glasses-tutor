import AVFoundation
import AudioToolbox

/// Speaks through whatever audio output is current. With the glasses connected
/// as the Bluetooth headset that is the glasses' speakers.
final class Speaker: NSObject {
    private let synthesizer = AVSpeechSynthesizer()
    private var last: (text: String, language: String)?

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

    func speak(_ text: String, language: String = "en-US") {
        activate()
        last = (text, language)
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: language)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }

    /// One tap on the touchpad: speaking → pause, paused → continue, silent → repeat the last answer.
    /// Returns a word for the log.
    @discardableResult
    func togglePause() -> String {
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
