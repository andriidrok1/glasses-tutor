import AVFoundation
import AudioToolbox

/// Speaks through whatever audio output is current. With the glasses connected
/// as the Bluetooth headset that is the glasses' speakers.
final class Speaker: NSObject {
    private let synthesizer = AVSpeechSynthesizer()

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

    func speak(_ text: String) {
        activate()
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }
}
