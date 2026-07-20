import Foundation

// MARK: - Developer Settings Manager
/// Manages developer settings storage and defaults.
/// Separate from the view controller to avoid circular dependencies with services.
final class DeveloperSettingsManager {

    // MARK: - Singleton
    static let shared = DeveloperSettingsManager()

    // MARK: - Keys
    private enum Keys {
        static let apiKey = "developer_apiKey"
        static let model = "developer_model"
        static let baseURL = "developer_baseURL"
        static let heartRegenerationInterval = "developer_heartRegenerationInterval"
        static let quizCostCoins = "developer_quizCostCoins"
        static let quizRewardCoins = "developer_quizRewardCoins"
        static let consecutiveVictoryBonusEnabled = "developer_consecutiveVictoryBonusEnabled"
        static let idiomChainCostCoins = "developer_idiomChainCostCoins"
        static let characterMatchCostCoins = "developer_characterMatchCostCoins"
    }

    private init() {}

    // MARK: - Hardcoded Defaults

    /// Default API key (hardcoded, used when no developer override is set).
    static let defaultAPIKey: String = "sk-1fb6a603205546358c1541c48ea579bd"

    /// Default model name.
    static let defaultModel: String = "qwen3-vl-plus"

    /// Default base URL.
    static let defaultBaseURL: String = "https://dashscope.aliyuncs.com/compatible-mode/v1"

    /// Default heart regeneration interval in seconds (10 minutes).
    static let defaultHeartRegenerationInterval: TimeInterval = 600

    /// Default coin cost to play a quiz level.
    static let defaultQuizCostCoins: Int = 1

    /// Default coin reward for complete victory in quiz.
    static let defaultQuizRewardCoins: Int = 3

    /// Default consecutive victory bonus enabled.
    static let defaultConsecutiveVictoryBonusEnabled: Bool = true

    /// Default coin cost to play Idiom Chain game.
    static let defaultIdiomChainCostCoins: Int = 10

    /// Default coin cost to play Character Match game.
    static let defaultCharacterMatchCostCoins: Int = 20

    // MARK: - Stored Values (Developer Overrides)

    var apiKey: String? {
        get { UserDefaults.standard.string(forKey: Keys.apiKey) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.apiKey) }
    }

    var model: String? {
        get { UserDefaults.standard.string(forKey: Keys.model) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.model) }
    }

    var baseURL: String? {
        get { UserDefaults.standard.string(forKey: Keys.baseURL) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.baseURL) }
    }

    /// Heart regeneration interval in seconds. Returns nil if default should be used.
    var heartRegenerationInterval: TimeInterval? {
        get {
            let key = Keys.heartRegenerationInterval
            guard UserDefaults.standard.object(forKey: key) != nil else { return nil }
            return UserDefaults.standard.double(forKey: key)
        }
        set {
            if let value = newValue {
                UserDefaults.standard.set(value, forKey: Keys.heartRegenerationInterval)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.heartRegenerationInterval)
            }
        }
    }

    /// Coin cost to play one quiz level. Returns nil if default should be used.
    var quizCostCoins: Int? {
        get {
            let key = Keys.quizCostCoins
            guard UserDefaults.standard.object(forKey: key) != nil else { return nil }
            return UserDefaults.standard.integer(forKey: key)
        }
        set {
            if let value = newValue {
                UserDefaults.standard.set(value, forKey: Keys.quizCostCoins)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.quizCostCoins)
            }
        }
    }

    /// Coin reward for complete victory in quiz. Returns nil if default should be used.
    var quizRewardCoins: Int? {
        get {
            let key = Keys.quizRewardCoins
            guard UserDefaults.standard.object(forKey: key) != nil else { return nil }
            return UserDefaults.standard.integer(forKey: key)
        }
        set {
            if let value = newValue {
                UserDefaults.standard.set(value, forKey: Keys.quizRewardCoins)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.quizRewardCoins)
            }
        }
    }

    /// Whether consecutive complete victory bonus is enabled.
    var consecutiveVictoryBonusEnabled: Bool? {
        get {
            let key = Keys.consecutiveVictoryBonusEnabled
            guard UserDefaults.standard.object(forKey: key) != nil else { return nil }
            return UserDefaults.standard.bool(forKey: key)
        }
        set {
            if let value = newValue {
                UserDefaults.standard.set(value, forKey: Keys.consecutiveVictoryBonusEnabled)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.consecutiveVictoryBonusEnabled)
            }
        }
    }

    /// Coin cost to play one Idiom Chain game. Returns nil if default should be used.
    var idiomChainCostCoins: Int? {
        get {
            let key = Keys.idiomChainCostCoins
            guard UserDefaults.standard.object(forKey: key) != nil else { return nil }
            return UserDefaults.standard.integer(forKey: key)
        }
        set {
            if let value = newValue {
                UserDefaults.standard.set(value, forKey: Keys.idiomChainCostCoins)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.idiomChainCostCoins)
            }
        }
    }

    /// Coin cost to play one Character Match game. Returns nil if default should be used.
    var characterMatchCostCoins: Int? {
        get {
            let key = Keys.characterMatchCostCoins
            guard UserDefaults.standard.object(forKey: key) != nil else { return nil }
            return UserDefaults.standard.integer(forKey: key)
        }
        set {
            if let value = newValue {
                UserDefaults.standard.set(value, forKey: Keys.characterMatchCostCoins)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.characterMatchCostCoins)
            }
        }
    }

    // MARK: - Effective Values (Developer Override > Default)

    /// Effective API key: developer override or hardcoded default.
    var effectiveAPIKey: String {
        if let stored = apiKey, !stored.isEmpty { return stored }
        return Self.defaultAPIKey
    }

    /// Effective model name.
    var effectiveModel: String {
        if let stored = model, !stored.isEmpty { return stored }
        return Self.defaultModel
    }

    /// Effective base URL.
    var effectiveBaseURL: String {
        if let stored = baseURL, !stored.isEmpty { return stored }
        return Self.defaultBaseURL
    }

    /// Effective heart regeneration interval (seconds).
    var effectiveHeartRegenerationInterval: TimeInterval {
        if let stored = heartRegenerationInterval, stored > 0 { return stored }
        return Self.defaultHeartRegenerationInterval
    }

    /// Effective coin cost to play one quiz level.
    var effectiveQuizCostCoins: Int {
        if let stored = quizCostCoins, stored >= 0 { return stored }
        return Self.defaultQuizCostCoins
    }

    /// Effective coin reward for complete victory.
    var effectiveQuizRewardCoins: Int {
        if let stored = quizRewardCoins, stored >= 0 { return stored }
        return Self.defaultQuizRewardCoins
    }

    /// Effective consecutive victory bonus toggle.
    var effectiveConsecutiveVictoryBonusEnabled: Bool {
        if let stored = consecutiveVictoryBonusEnabled { return stored }
        return Self.defaultConsecutiveVictoryBonusEnabled
    }

    /// Effective coin cost to play one Idiom Chain game.
    var effectiveIdiomChainCostCoins: Int {
        if let stored = idiomChainCostCoins, stored >= 0 { return stored }
        return Self.defaultIdiomChainCostCoins
    }

    /// Effective coin cost to play one Character Match game.
    var effectiveCharacterMatchCostCoins: Int {
        if let stored = characterMatchCostCoins, stored >= 0 { return stored }
        return Self.defaultCharacterMatchCostCoins
    }

    // MARK: - Reset

    /// Clears all developer overrides, reverting to defaults.
    func resetToDefaults() {
        UserDefaults.standard.removeObject(forKey: Keys.apiKey)
        UserDefaults.standard.removeObject(forKey: Keys.model)
        UserDefaults.standard.removeObject(forKey: Keys.baseURL)
        UserDefaults.standard.removeObject(forKey: Keys.heartRegenerationInterval)
        UserDefaults.standard.removeObject(forKey: Keys.quizCostCoins)
        UserDefaults.standard.removeObject(forKey: Keys.quizRewardCoins)
        UserDefaults.standard.removeObject(forKey: Keys.consecutiveVictoryBonusEnabled)
        UserDefaults.standard.removeObject(forKey: Keys.idiomChainCostCoins)
        UserDefaults.standard.removeObject(forKey: Keys.characterMatchCostCoins)
    }
}
