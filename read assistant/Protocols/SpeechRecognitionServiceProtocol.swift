import Foundation

// MARK: - Speech Recognition Service Protocol (Pluggable)
/// Protocol defining the speech-to-text (ASR) service interface.
/// Implementations can use Apple's SFSpeechRecognizer or third-party engines.
protocol SpeechRecognitionServiceProtocol: AnyObject {

    /// Current recognition state.
    var isRecognizing: Bool { get }

    /// Delegate to receive recognition results.
    var delegate: SpeechRecognitionServiceDelegate? { get set }

    /// Starts speech recognition from the device microphone.
    /// - Parameter locale: The locale for recognition (e.g., "zh-CN").
    /// - Throws: Error if microphone access is denied or recognizer is unavailable.
    func startRecognition(locale: Locale) throws

    /// Pauses ongoing recognition (keeps session alive).
    func pauseRecognition()

    /// Resumes a paused recognition session.
    func resumeRecognition() throws

    /// Stops recognition and finalizes the result.
    func stopRecognition()
}

// MARK: - Speech Recognition Delegate
protocol SpeechRecognitionServiceDelegate: AnyObject {
    /// Called when a partial (interim) transcription is available.
    func speechRecognitionService(_ service: Any, didProducePartialResult text: String)

    /// Called when a final transcription segment is ready.
    func speechRecognitionService(_ service: Any, didProduceFinalResult text: String)

    /// Called when an error occurs during recognition.
    func speechRecognitionService(_ service: Any, didEncounterError error: Error)

    /// Called when recognition completes.
    func speechRecognitionServiceDidFinish(_ service: Any)
}

// MARK: - Speech Recognition Errors
enum SpeechRecognitionError: LocalizedError {
    case notAuthorized
    case recognizerUnavailable
    case audioEngineError(String)
    case recognitionInProgress
    case microphoneAccessDenied

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "未授权语音识别，请在设置中开启权限"
        case .recognizerUnavailable:
            return "语音识别器不可用"
        case .audioEngineError(let detail):
            return "音频引擎错误：\(detail)"
        case .recognitionInProgress:
            return "识别已在进行中"
        case .microphoneAccessDenied:
            return "麦克风访问被拒绝"
        }
    }
}
