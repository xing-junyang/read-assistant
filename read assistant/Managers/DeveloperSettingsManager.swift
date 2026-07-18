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
    }

    private init() {}

    // MARK: - Hardcoded Defaults

    /// Default API key (hardcoded, used when no developer override is set).
    static let defaultAPIKey: String = "sk-1fb6a603205546358c1541c48ea579bd"

    /// Default model name.
    static let defaultModel: String = "qwen3-vl-plus"

    /// Default base URL.
    static let defaultBaseURL: String = "https://dashscope.aliyuncs.com/compatible-mode/v1"

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

    // MARK: - Reset

    /// Clears all developer overrides, reverting to defaults.
    func resetToDefaults() {
        UserDefaults.standard.removeObject(forKey: Keys.apiKey)
        UserDefaults.standard.removeObject(forKey: Keys.model)
        UserDefaults.standard.removeObject(forKey: Keys.baseURL)
    }
}
