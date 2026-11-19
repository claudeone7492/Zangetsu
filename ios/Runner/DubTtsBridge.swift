import AVFoundation
import Flutter

/// System text-to-speech behind AI Dub, on the same channel as Android.
///
/// AVSpeechSynthesizer needs no permission and no download for the built-in
/// voices, so the light path works on a fresh install. The device's full voice
/// list is only exposed once the audio session is active, so voices are read
/// from `speechVoices()` and marked network-only where they are enhanced or
/// premium — those are the ones that need a download.
final class DubTtsBridge {
  private let synthesizer = AVSpeechSynthesizer()
  private var cachedVoices: [[String: Any]]?

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "available":
      result(true)
    case "voices":
      result(voices())
    case "speak":
      guard let args = call.arguments as? [String: Any],
            let text = args["text"] as? String, !text.isEmpty else {
        result(nil)
        return
      }
      speak(
        text: text,
        voice: args["voice"] as? String,
        rate: (args["rate"] as? Double) ?? 1.0,
        pitch: (args["pitch"] as? Double) ?? 1.0,
        volume: (args["volume"] as? Double) ?? 1.0
      )
      result(nil)
    case "stop":
      if synthesizer.isSpeaking {
        synthesizer.stopSpeaking(at: .immediate)
      }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func voices() -> [[String: Any]] {
    if let cached = cachedVoices { return cached }
    let mapped: [[String: Any]] = AVSpeechSynthesisVoice.speechVoices().map { v in
      // "com.apple.voice.enhanced.en-US.Samantha" / "...premium..." need a
      // download; the compact ones are always present.
      let network = v.identifier.contains(".enhanced.") || v.identifier.contains(".premium.")
      return [
        "name": v.name,
        "locale": v.language,
        "network": network,
        // The identifier is what `speak` matches on; the name is not unique
        // across locales.
        "id": v.identifier,
      ]
    }
    let sorted = mapped.sorted { a, b in
      let an = (a["network"] as? Bool) ?? false
      let bn = (b["network"] as? Bool) ?? false
      if an != bn { return !an }
      return ((a["name"] as? String) ?? "") < ((b["name"] as? String) ?? "")
    }
    cachedVoices = sorted
    return sorted
  }

  private func speak(text: String, voice: String?, rate: Double, pitch: Double, volume: Double) {
    // A new line replaces the previous one, matching Android's QUEUE_FLUSH.
    if synthesizer.isSpeaking {
      synthesizer.stopSpeaking(at: .immediate)
    }
    let utterance = AVSpeechUtterance(string: text)
    if let wanted = voice {
      // Match on identifier first, then on language tag, so a saved voice that
      // vanished falls back to the same language instead of the system default.
      if let match = AVSpeechSynthesisVoice.speechVoices().first(where: {
        $0.identifier == wanted || $0.name == wanted
      }) {
        utterance.voice = match
      } else if let byLanguage = AVSpeechSynthesisVoice(language: wanted) {
        utterance.voice = byLanguage
      }
    }
    // AVSpeechUtterance's rate is 0…1 with a default near 0.5, so the app's
    // 0.5…2.0 multiplier is mapped onto that range rather than passed through.
    utterance.rate = AVSpeechUtteranceDefaultSpeechRate * Float(rate)
    utterance.pitchMultiplier = Float(pitch)
    utterance.volume = Float(volume)
    synthesizer.speak(utterance)
  }

  func dispose() {
    if synthesizer.isSpeaking {
      synthesizer.stopSpeaking(at: .immediate)
    }
    cachedVoices = nil
  }
}
