import AppKit
import AVFoundation
import Observation
import SaywellCore

/// Text-to-speech for practice. The voice is chosen per language; nothing is hardcoded to English.
@MainActor @Observable final class SpeechService: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?
    private(set) var speaking = false

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    static func voices(for languageID: String) -> [AVSpeechSynthesisVoice] {
        guard let info = LanguageCatalog.info(languageID) else { return [] }
        let prefix = info.appleLocale.replacingOccurrences(of: "_", with: "-").prefix(2)
        return AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(prefix) }
            .sorted { ($0.quality.rawValue, $0.name) > ($1.quality.rawValue, $1.name) }
    }

    static func hasVoice(for languageID: String) -> Bool { !voices(for: languageID).isEmpty }

    func speak(_ text: String, languageID: String, settings: SpeechSettings) {
        stop()
        let utterance = AVSpeechUtterance(string: text)
        if let id = settings.voices[languageID], let voice = AVSpeechSynthesisVoice(identifier: id) {
            utterance.voice = voice
        } else if let info = LanguageCatalog.info(languageID) {
            utterance.voice = Self.voices(for: languageID).first ?? AVSpeechSynthesisVoice(language: info.appleLocale.replacingOccurrences(of: "_", with: "-"))
        }
        utterance.rate = Float(settings.rate)
        speaking = true
        synthesizer.speak(utterance)
    }

    func play(_ url: URL) {
        stop()
        player = try? AVAudioPlayer(contentsOf: url)
        player?.play()
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        player?.stop()
        speaking = false
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.speaking = false }
    }
}

/// Optional, quiet system sounds for start, done and error. Off by default.
enum Sound {
    enum Cue { case start, done, error }

    @MainActor static func play(_ cue: Cue, enabled: Bool) {
        guard enabled else { return }
        let name = switch cue {
        case .start: "Tink"
        case .done: "Pop"
        case .error: "Basso"
        }
        guard let sound = NSSound(named: NSSound.Name(name)) else { return }
        sound.volume = 0.35
        sound.play()
    }
}
