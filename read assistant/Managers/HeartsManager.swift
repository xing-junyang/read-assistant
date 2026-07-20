import Foundation

// MARK: - Hearts Manager
/// Manages the hearts (红心) system: regeneration, consumption, purchase, and limits.
/// Hearts regenerate automatically at 1 per 10 minutes, up to a configurable maximum.
/// Supports an "unlimited hearts" developer mode.
final class HeartsManager {

    // MARK: - Singleton
    static let shared = HeartsManager()

    // MARK: - UserDefaults Keys
    private enum Key {
        static let hearts = "hearts_count"
        static let maxHearts = "hearts_max"
        static let lastUpdateTime = "hearts_last_update_time"
        static let unlimitedHearts = "hearts_unlimited"
    }

    // MARK: - Constants
    /// Default seconds between heart regeneration (10 minutes).
    static let defaultHeartRegenerationInterval: TimeInterval = 600
    /// Default maximum hearts.
    static let defaultMaxHearts = 10
    /// Absolute maximum hearts cap.
    static let absoluteMaxHearts = 30
    /// Increment when purchasing max hearts upgrade.
    static let maxHeartsUpgradeAmount = 2

    /// Current heart regeneration interval (developer-configurable).
    var heartRegenerationInterval: TimeInterval {
        return DeveloperSettingsManager.shared.effectiveHeartRegenerationInterval
    }

    // MARK: - Properties
    private let defaults = UserDefaults.standard

    /// Current heart count (before regeneration calculation).
    private var storedHearts: Int {
        get { return defaults.integer(forKey: Key.hearts) }
        set { defaults.set(newValue, forKey: Key.hearts) }
    }

    /// Maximum hearts capacity.
    var maxHearts: Int {
        get {
            let value = defaults.integer(forKey: Key.maxHearts)
            return value > 0 ? value : Self.defaultMaxHearts
        }
        set {
            defaults.set(min(newValue, Self.absoluteMaxHearts), forKey: Key.maxHearts)
        }
    }

    /// Timestamp (seconds since 1970) of the last hearts update.
    private var lastUpdateTime: TimeInterval {
        get {
            let value = defaults.double(forKey: Key.lastUpdateTime)
            return value > 0 ? value : Date().timeIntervalSince1970
        }
        set {
            defaults.set(newValue, forKey: Key.lastUpdateTime)
        }
    }

    /// Whether unlimited hearts mode is enabled (developer setting).
    var unlimitedHearts: Bool {
        get { return defaults.bool(forKey: Key.unlimitedHearts) }
        set { defaults.set(newValue, forKey: Key.unlimitedHearts) }
    }

    // MARK: - Initialization
    private init() {
        // Initialize defaults
        if defaults.object(forKey: Key.maxHearts) == nil {
            maxHearts = Self.defaultMaxHearts
        }
        if defaults.object(forKey: Key.hearts) == nil {
            storedHearts = maxHearts
            lastUpdateTime = Date().timeIntervalSince1970
        }
    }

    // MARK: - Heart Regeneration

    /// Recalculates hearts based on elapsed time and returns the current count.
    /// Call this before reading or displaying hearts to get up-to-date values.
    @discardableResult
    func refreshHearts() -> Int {
        if unlimitedHearts {
            storedHearts = maxHearts
            lastUpdateTime = Date().timeIntervalSince1970
            return maxHearts
        }

        let now = Date().timeIntervalSince1970
        let elapsed = now - lastUpdateTime

        guard elapsed >= heartRegenerationInterval else {
            return storedHearts
        }

        let regenerated = Int(elapsed / heartRegenerationInterval)
        let newHearts = min(maxHearts, storedHearts + regenerated)
        storedHearts = newHearts

        // Advance the timestamp by exactly the regenerated interval
        lastUpdateTime += Double(regenerated) * heartRegenerationInterval

        return newHearts
    }

    /// Current hearts count (after regeneration).
    var hearts: Int {
        return refreshHearts()
    }

    // MARK: - Seconds Until Next Heart

    /// Seconds remaining until the next heart regenerates.
    /// Returns 0 if hearts are already at max or unlimited mode is on.
    var secondsUntilNextHeart: TimeInterval {
        if unlimitedHearts || storedHearts >= maxHearts {
            return 0
        }

        let now = Date().timeIntervalSince1970
        let elapsed = now - lastUpdateTime
        let remaining = heartRegenerationInterval - elapsed.truncatingRemainder(dividingBy: heartRegenerationInterval)
        return remaining
    }

    /// Formatted string for the next heart regeneration time (e.g., "08:32").
    var nextHeartTimeFormatted: String {
        let remaining = secondsUntilNextHeart
        guard remaining > 0 else { return "已满" }

        let minutes = Int(remaining) / 60
        let seconds = Int(remaining) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// Total seconds until hearts are fully refilled.
    var secondsUntilFull: TimeInterval {
        if unlimitedHearts {
            return 0
        }
        let current = storedHearts
        guard current < maxHearts else { return 0 }

        let heartsNeeded = maxHearts - current
        let now = Date().timeIntervalSince1970
        let elapsed = now - lastUpdateTime
        let timeSinceLastHeart = elapsed.truncatingRemainder(dividingBy: heartRegenerationInterval)
        let timeToNextHeart = heartRegenerationInterval - timeSinceLastHeart

        // First heart comes after timeToNextHeart, remaining hearts come every configured interval
        return timeToNextHeart + Double(heartsNeeded - 1) * heartRegenerationInterval
    }

    // MARK: - Heart Consumption

    /// Attempts to consume one heart for a reading session.
    /// - Returns: `true` if consumption succeeded, `false` if no hearts available.
    func consumeHeart() -> Bool {
        refreshHearts()

        if unlimitedHearts {
            return true
        }

        guard storedHearts > 0 else {
            return false
        }

        storedHearts -= 1
        return true
    }

    // MARK: - Shop Actions

    /// Buys 5 hearts for coins. Hearts cannot exceed max.
    /// - Returns: The number of hearts actually added.
    func buyFiveHearts() -> Int {
        refreshHearts()

        let space = maxHearts - storedHearts
        guard space > 0 else { return 0 }

        let added = min(5, space)
        storedHearts += added

        // Reset regeneration timer if we're now at max
        if storedHearts >= maxHearts {
            lastUpdateTime = Date().timeIntervalSince1970
        }

        return added
    }

    /// Refills hearts to maximum.
    /// - Returns: The number of hearts added.
    func refillHearts() -> Int {
        refreshHearts()

        let space = maxHearts - storedHearts
        guard space > 0 else { return 0 }

        storedHearts = maxHearts
        lastUpdateTime = Date().timeIntervalSince1970
        return space
    }

    /// Increases max hearts by `Self.maxHeartsUpgradeAmount` (2), up to `Self.absoluteMaxHearts` (30).
    /// - Returns: `true` if upgrade succeeded, `false` if already at the absolute maximum.
    func upgradeMaxHearts() -> Bool {
        guard maxHearts < Self.absoluteMaxHearts else {
            return false
        }

        maxHearts = min(maxHearts + Self.maxHeartsUpgradeAmount, Self.absoluteMaxHearts)
        return true
    }

    /// Whether the user can still upgrade max hearts.
    var canUpgradeMaxHearts: Bool {
        return maxHearts < Self.absoluteMaxHearts
    }

    // MARK: - Developer Debug

    /// Sets hearts to a specific count (clamped to valid range).
    func debugSetHearts(_ count: Int) {
        storedHearts = max(0, min(count, maxHearts))
        if storedHearts >= maxHearts {
            lastUpdateTime = Date().timeIntervalSince1970
        }
    }

    /// Sets max hearts to a specific value.
    func debugSetMaxHearts(_ count: Int) {
        maxHearts = max(1, min(count, Self.absoluteMaxHearts))
        if storedHearts > maxHearts {
            storedHearts = maxHearts
            lastUpdateTime = Date().timeIntervalSince1970
        }
    }

    /// Refills hearts to max (debug convenience).
    func debugRefillHearts() {
        storedHearts = maxHearts
        lastUpdateTime = Date().timeIntervalSince1970
    }
}
