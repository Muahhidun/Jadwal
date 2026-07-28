import AVFoundation
import Flutter
import MediaPlayer
import UIKit

/// Нативный голосовой движок чтеца зикров (AVSpeechSynthesizer + AVSpeechSynthesisVoice ar-SA).
/// Воспроизводит арабские тексты зикров с комфортным темпом и паузами для повторения за голосом.
public final class ZikrSpeechManager: NSObject, FlutterPlugin, AVSpeechSynthesizerDelegate {
  static let channelName = "kz.dauam/speech"
  public static let shared = ZikrSpeechManager()

  private let synthesizer = AVSpeechSynthesizer()
  private var currentUtterances: [String] = []
  private var currentTitle: String = ""
  private var currentIndex: Int = 0
  private var isPlayingState: Bool = false
  private var channel: FlutterMethodChannel?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: registrar.messenger()
    )
    shared.channel = channel
    registrar.addMethodCallDelegate(shared, channel: channel)
  }

  private override init() {
    super.init()
    synthesizer.delegate = self
    setupRemoteTransportControls()
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "speakZikrs":
      guard let args = call.arguments as? [String: Any],
            let items = args["items"] as? [String],
            let title = args["title"] as? String else {
        result(FlutterError(code: "INVALID_ARGS", message: "Expected items array and title", details: nil))
        return
      }
      let pauseSeconds = args["pauseSeconds"] as? Double ?? 2.5
      startReading(items: items, title: title, pauseSeconds: pauseSeconds)
      result(true)

    case "pause":
      pauseReading()
      result(true)

    case "resume":
      resumeReading()
      result(true)

    case "stop":
      stopReading()
      result(true)

    case "isSpeaking":
      result(synthesizer.isSpeaking)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  public func startReading(items: [String], title: String, pauseSeconds: Double) {
    stopReading()

    guard !items.isEmpty else { return }
    currentUtterances = items
    currentTitle = title
    currentIndex = 0
    isPlayingState = true

    configureAudioSession()
    speakCurrentIndex(pauseSeconds: pauseSeconds)
  }

  private func speakCurrentIndex(pauseSeconds: Double) {
    guard currentIndex < currentUtterances.count else {
      stopReading()
      channel?.invokeMethod("onReadingCompleted", arguments: nil)
      return
    }

    let text = currentUtterances[currentIndex]
    let utterance = AVSpeechUtterance(string: text)

    // Голос: арабский (ar-SA / ar-AE / ar)
    if let voice = AVSpeechSynthesisVoice(language: "ar-SA") ?? AVSpeechSynthesisVoice(language: "ar-AE") ?? AVSpeechSynthesisVoice(language: "ar") {
      utterance.voice = voice
    }

    // Спокойный, размеренный темп для повторения
    utterance.rate = 0.46
    utterance.pitchMultiplier = 1.0
    utterance.postUtteranceDelay = pauseSeconds

    updateNowPlayingInfo()
    channel?.invokeMethod("onZikrStarted", arguments: ["index": currentIndex, "total": currentUtterances.count])

    synthesizer.speak(utterance)
  }

  public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
    guard isPlayingState else { return }
    currentIndex += 1
    if currentIndex < currentUtterances.count {
      speakCurrentIndex(pauseSeconds: utterance.postUtteranceDelay)
    } else {
      stopReading()
      channel?.invokeMethod("onReadingCompleted", arguments: nil)
    }
  }

  public func pauseReading() {
    if synthesizer.isSpeaking {
      synthesizer.pauseSpeaking(at: .immediate)
      isPlayingState = false
      updateNowPlayingInfo()
    }
  }

  public func resumeReading() {
    if synthesizer.isPaused {
      synthesizer.continueSpeaking()
      isPlayingState = true
      updateNowPlayingInfo()
    }
  }

  public func stopReading() {
    isPlayingState = false
    if synthesizer.isSpeaking || synthesizer.isPaused {
      synthesizer.stopSpeaking(at: .immediate)
    }
    currentUtterances.removeAll()
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
  }

  private func configureAudioSession() {
    let session = AVAudioSession.sharedInstance()
    try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
    try? session.setActive(true, options: .notifyOthersOnDeactivation)
  }

  private func setupRemoteTransportControls() {
    let commandCenter = MPRemoteCommandCenter.shared()
    commandCenter.playCommand.isEnabled = true
    commandCenter.playCommand.addTarget { [weak self] _ in
      self?.resumeReading()
      return .success
    }

    commandCenter.pauseCommand.isEnabled = true
    commandCenter.pauseCommand.addTarget { [weak self] _ in
      self?.pauseReading()
      return .success
    }

    commandCenter.togglePlayPauseCommand.isEnabled = true
    commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
      guard let self = self else { return .commandFailed }
      if self.synthesizer.isPaused {
        self.resumeReading()
      } else if self.synthesizer.isSpeaking {
        self.pauseReading()
      }
      return .success
    }
  }

  private func updateNowPlayingInfo() {
    var nowPlayingInfo = [String: Any]()
    nowPlayingInfo[MPMediaItemPropertyTitle] = "\(currentTitle) (\(currentIndex + 1)/\(currentUtterances.count))"
    nowPlayingInfo[MPMediaItemPropertyArtist] = "Dauam · دوام"
    nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlayingState ? 1.0 : 0.0

    MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
  }
}
