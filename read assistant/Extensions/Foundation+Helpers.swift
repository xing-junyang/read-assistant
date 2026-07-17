import UIKit

// MARK: - Date Formatter Extension
extension Date {
    /// Returns a short Chinese-formatted date string.
    var shortChineseFormat: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日 HH:mm"
        return formatter.string(from: self)
    }
}

// MARK: - String Extension
extension String {
    /// Truncates the string to a maximum length with an ellipsis.
    func truncated(_ maxLength: Int) -> String {
        if self.count <= maxLength { return self }
        let endIndex = self.index(self.startIndex, offsetBy: maxLength)
        return String(self[..<endIndex]) + "..."
    }
}
