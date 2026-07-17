import AVFoundation

// MARK: - Audio Session Manager
/// Manages AVAudioSession configuration for recording and playback.
/// Handles iOS 10 compatible audio session setup.
final class AudioSessionManager {

    // MARK: - Singleton
    static let shared = AudioSessionManager()

    private let session = AVAudioSession.sharedInstance()

    private init() {}

    // MARK: - Session Configuration

    /// Requests recording permission from the user.
    func requestRecordingPermission(completion: @escaping (Bool) -> Void) {
        // AVAudioSessionRecordPermission available iOS 8+
        switch session.recordPermission() {
        case .granted:
            completion(true)
        case .denied:
            completion(false)
        case .undetermined:
            session.requestRecordPermission { granted in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        @unknown default:
            completion(false)
        }
    }

    /// Configures the audio session for recording.
    func configureForRecording() throws {
        try session.setCategory(.playAndRecord, mode: .default)
        try session.setActive(true, options: [])
    }

    /// Configures the audio session for playback only.
    func configureForPlayback() throws {
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true, options: [])
    }

    /// Deactivates the audio session.
    func deactivate() throws {
        try session.setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Returns whether recording permission is granted.
    var hasRecordingPermission: Bool {
        return session.recordPermission() == .granted
    }
}
