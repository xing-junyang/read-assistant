import Foundation

// MARK: - Custom Idiom Manager
/// Manages user-imported custom idioms (四字词语) stored in UserDefaults.
final class CustomIdiomManager {

    // MARK: - Singleton
    static let shared = CustomIdiomManager()

    // MARK: - Keys
    private enum Key {
        static let customIdioms = "custom_idioms"
    }

    private let defaults = UserDefaults.standard

    // MARK: - Properties
    /// All user-imported idioms.
    var customIdioms: [String] {
        get { return defaults.stringArray(forKey: Key.customIdioms) ?? [] }
        set { defaults.set(newValue, forKey: Key.customIdioms) }
    }

    private init() {}

    // MARK: - Import

    /// Imports idioms from a text string. Each idiom must be exactly 4 Chinese characters,
    /// separated by whitespace, newlines, commas, or Chinese punctuation.
    /// Returns count of successfully imported idioms.
    @discardableResult
    func importIdioms(from text: String) -> Int {
        // Split by common separators
        let separators = CharacterSet.whitespacesAndNewlines
            .union(CharacterSet(charactersIn: "，,。、；;：:！!？?"))
        let words = text.components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { isValidIdiom($0) }

        var current = customIdioms
        var added = 0
        for word in words {
            if !current.contains(word) {
                current.append(word)
                added += 1
            }
        }
        customIdioms = current
        return added
    }

    /// Adds a single idiom.
    func addIdiom(_ idiom: String) -> Bool {
        guard isValidIdiom(idiom) else { return false }
        var current = customIdioms
        if current.contains(idiom) { return false }
        current.append(idiom)
        customIdioms = current
        return true
    }

    /// Removes an idiom at the given index.
    func removeIdiom(at index: Int) {
        var current = customIdioms
        guard index < current.count else { return }
        current.remove(at: index)
        customIdioms = current
    }

    /// Clears all custom idioms.
    func clearAll() {
        customIdioms = []
    }

    // MARK: - Validation

    /// Checks if a string is a valid 4-character CJK idiom.
    func isValidIdiom(_ text: String) -> Bool {
        guard text.count == 4 else { return false }
        return text.unicodeScalars.allSatisfy { scalar in
            let v = scalar.value
            return (v >= 0x4E00 && v <= 0x9FFF) || (v >= 0x3400 && v <= 0x4DBF)
        }
    }
}
