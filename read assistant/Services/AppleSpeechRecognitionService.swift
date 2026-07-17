import Foundation
import Speech
import AVFoundation

// MARK: - Apple Speech Recognition Service
/// Speech-to-text implementation using Apple's SFSpeechRecognizer (iOS 10+).
/// Supports offline recognition for Chinese and other supported languages.
final class AppleSpeechRecognitionService: NSObject, SpeechRecognitionServiceProtocol {

    // MARK: - Properties
    private let speechRecognizer: SFSpeechRecognizer
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var accumulatedText = ""
    private var isPaused = false

    weak var delegate: SpeechRecognitionServiceDelegate?

    var isRecognizing: Bool {
        return recognitionTask != nil && !isPaused
    }

    // MARK: - Initialization
    init(locale: Locale = Locale(identifier: "zh-CN")) {
        self.speechRecognizer = SFSpeechRecognizer(locale: locale)!
        super.init()
        self.speechRecognizer.delegate = self
    }

    deinit {
        stopRecognition()
        audioEngine.stop()
    }

    // MARK: - SpeechRecognitionServiceProtocol

    func startRecognition(locale: Locale) throws {
        guard !isRecognizing else {
            throw SpeechRecognitionError.recognitionInProgress
        }

        guard speechRecognizer.isAvailable else {
            throw SpeechRecognitionError.recognizerUnavailable
        }

        // Reset state
        accumulatedText = ""
        isPaused = false

        // Configure audio session
        try AudioSessionManager.shared.configureForRecording()

        // Cancel any previous task
        recognitionTask?.cancel()
        recognitionTask = nil

        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()

        guard let recognitionRequest = recognitionRequest else {
            throw SpeechRecognitionError.audioEngineError("无法创建识别请求")
        }

        // Configure for partial results
        recognitionRequest.shouldReportPartialResults = true

        // Set up audio input
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        // Start audio engine
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            throw SpeechRecognitionError.audioEngineError(error.localizedDescription)
        }

        // Start recognition
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }

            if let error = error {
                DispatchQueue.main.async {
                    self.delegate?.speechRecognitionService(self, didEncounterError: error)
                }
                return
            }

            guard let result = result else { return }

            let transcribedText = result.bestTranscription.formattedString

            if result.isFinal {
                self.accumulatedText = transcribedText
                DispatchQueue.main.async {
                    self.delegate?.speechRecognitionService(self, didProduceFinalResult: transcribedText)
                    self.delegate?.speechRecognitionServiceDidFinish(self)
                }
            } else if !self.isPaused {
                self.accumulatedText = transcribedText
                DispatchQueue.main.async {
                    self.delegate?.speechRecognitionService(self, didProducePartialResult: transcribedText)
                }
            }
        }
    }

    func pauseRecognition() {
        guard recognitionTask != nil else { return }
        isPaused = true
        // Keep audio engine running but ignore results
    }

    func resumeRecognition() throws {
        guard isPaused else { return }
        isPaused = false
    }

    func stopRecognition() {
        // Remove tap
        audioEngine.inputNode.removeTap(onBus: 0)

        // End recognition
        recognitionRequest?.endAudio()
        recognitionTask?.finish()

        recognitionRequest = nil
        recognitionTask = nil
        isPaused = false

        // Stop audio engine
        audioEngine.stop()

        // Deactivate audio session
        try? AudioSessionManager.shared.deactivate()
    }

    // MARK: - Helpers

    /// Returns the full accumulated text so far.
    var fullRecognizedText: String {
        return accumulatedText
    }
}

// MARK: - SFSpeechRecognizerDelegate
extension AppleSpeechRecognitionService: SFSpeechRecognizerDelegate {
    func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        if !available {
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.speechRecognitionService(self, didEncounterError: SpeechRecognitionError.recognizerUnavailable)
            }
        }
    }
}
