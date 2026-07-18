import Foundation
import AVFoundation

// MARK: - Audio Recording Manager
/// Manages audio recording to a file using AVAudioRecorder.
/// Supports pause/resume and provides the file path for later playback.
final class AudioRecordingManager: NSObject {

    // MARK: - Singleton
    static let shared = AudioRecordingManager()

    // MARK: - Properties
    private var audioRecorder: AVAudioRecorder?
    private(set) var currentFilePath: String?
    private(set) var isRecording = false
    private(set) var isPaused = false

    /// Callback when recording is interrupted (e.g., phone call).
    var onInterruption: ((Bool) -> Void)?

    // MARK: - Initialization
    private override init() {
        super.init()
        setupInterruptionNotification()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Public API

    /// Starts a new recording session. Creates a new audio file.
    /// - Returns: The file path where audio will be saved.
    func startRecording() throws -> String {
        // Stop any existing recording
        if isRecording {
            stopRecording(keepFile: false)
        }

        // Configure audio session for recording
        try AudioSessionManager.shared.configureForRecording()

        // Generate a unique file path
        let filePath = generateAudioFilePath()
        let url = URL(fileURLWithPath: filePath)

        // Audio settings: AAC format, good quality, mono
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            AVEncoderBitRateKey: 128000
        ]

        audioRecorder = try AVAudioRecorder(url: url, settings: settings)
        audioRecorder?.delegate = self
        audioRecorder?.isMeteringEnabled = true

        guard audioRecorder?.record() == true else {
            throw AudioRecordingError.recordFailed
        }

        currentFilePath = filePath
        isRecording = true
        isPaused = false

        return filePath
    }

    /// Pauses the current recording. Can be resumed later.
    func pauseRecording() {
        guard isRecording, !isPaused else { return }
        audioRecorder?.pause()
        isPaused = true
    }

    /// Resumes a paused recording.
    func resumeRecording() {
        guard isRecording, isPaused else { return }
        audioRecorder?.record()
        isPaused = false
    }

    /// Stops the current recording and finalizes the audio file.
    /// - Parameter keepFile: If false, deletes the recorded file.
    func stopRecording(keepFile: Bool = true) {
        audioRecorder?.stop()
        audioRecorder = nil

        if !keepFile, let path = currentFilePath {
            try? FileManager.default.removeItem(atPath: path)
        }

        isRecording = false
        isPaused = false
    }

    /// Deletes the audio file at the given path.
    static func deleteAudioFile(at path: String) {
        guard FileManager.default.fileExists(atPath: path) else { return }
        try? FileManager.default.removeItem(atPath: path)
    }

    /// Checks if an audio file exists at the given path.
    static func audioFileExists(at path: String) -> Bool {
        return FileManager.default.fileExists(atPath: path)
    }

    // MARK: - File Path Generation

    /// Generates a unique audio file path in the AudioRecordings directory.
    /// Uses .caf (Core Audio Format) which is the native format for audio recorded
    /// via AVAudioEngine tap buffers (linear PCM). This format is lossless and
    /// avoids the transcoding issues that can occur with compressed formats like AAC.
    static func generateAudioFilePath() -> String {
        let docsDir = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!
        let audioDir = URL(fileURLWithPath: docsDir).appendingPathComponent("AudioRecordings").path

        // Create directory if it doesn't exist
        if !FileManager.default.fileExists(atPath: audioDir) {
            try? FileManager.default.createDirectory(atPath: audioDir, withIntermediateDirectories: true)
        }

        let fileName = "recording_\(UUID().uuidString).caf"
        return URL(fileURLWithPath: audioDir).appendingPathComponent(fileName).path
    }

    private func generateAudioFilePath() -> String {
        return Self.generateAudioFilePath()
    }

    // MARK: - Interruption Handling

    private func setupInterruptionNotification() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioSessionInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
    }

    @objc private func handleAudioSessionInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            // Auto-pause on interruption
            if isRecording, !isPaused {
                pauseRecording()
            }
            onInterruption?(true)

        case .ended:
            onInterruption?(false)

        @unknown default:
            break
        }
    }
}

// MARK: - AVAudioRecorderDelegate
extension AudioRecordingManager: AVAudioRecorderDelegate {
    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag, let path = currentFilePath {
            try? FileManager.default.removeItem(atPath: path)
            currentFilePath = nil
        }
        isRecording = false
        isPaused = false
        audioRecorder = nil
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        if let error = error {
            print("[AudioRecordingManager] Encode error: \(error.localizedDescription)")
        }
    }
}

// MARK: - Audio Recording Errors
enum AudioRecordingError: LocalizedError {
    case recordFailed
    case playbackFailed

    var errorDescription: String? {
        switch self {
        case .recordFailed:
            return "录音启动失败"
        case .playbackFailed:
            return "音频播放失败"
        }
    }
}
