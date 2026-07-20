import UIKit
import AudioToolbox

// MARK: - Sound Effect Manager
/// Plays system sound effects for various app events.
/// Uses AudioToolbox system sounds for iOS 10 compatibility.
final class SoundEffectManager {

    // MARK: - Singleton
    static let shared = SoundEffectManager()

    // MARK: - Initialization
    private init() {}

    // MARK: - Sound Effects

    /// Plays a completion/achievement sound when reading is finished.
    /// Uses system sound 1057 (a pleasant ascending tone) which works offline
    /// and does not require bundled audio files.
    func playCompletionSound() {
        // SystemSoundID 1057: "Tink" sound — short, pleasant, completion-like
        // SystemSoundID 1025: "Morse" — also works well
        // SystemSoundID 1000: "New Mail" — familiar completion sound
        playSystemSound(1057)
    }

    /// Plays a level-up celebration sound.
    func playLevelUpSound() {
        // SystemSoundID 1025: ascending chime
        playSystemSound(1025)
    }

    /// Plays a coin/reward received sound.
    func playCoinSound() {
        // SystemSoundID 1003: short crisp sound
        playSystemSound(1003)
    }

    /// Plays a button tap / UI interaction sound.
    func playTapSound() {
        playSystemSound(1104)
    }

    /// Plays a correct answer sound for quiz.
    func playQuizCorrectSound() {
        // SystemSoundID 1057: pleasant ascending "Tink" tone
        playSystemSound(1057)
    }

    /// Plays an incorrect answer sound for quiz.
    func playQuizIncorrectSound() {
        // SystemSoundID 1053: short descending tone
        playSystemSound(1053)
    }

    /// Plays a quiz level completion / victory sound.
    func playQuizVictorySound() {
        // SystemSoundID 1025: ascending chime
        playSystemSound(1025)
    }

    /// Plays a quiz failure sound.
    func playQuizFailureSound() {
        // SystemSoundID 1006: low alert tone
        playSystemSound(1006)
    }

    // MARK: - Private

    private func playSystemSound(_ soundID: SystemSoundID) {
        AudioServicesPlaySystemSound(soundID)
    }
}
