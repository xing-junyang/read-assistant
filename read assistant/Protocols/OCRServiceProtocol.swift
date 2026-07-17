import UIKit

// MARK: - OCR Service Protocol (Pluggable)
/// Protocol defining the OCR (Optical Character Recognition) service interface.
/// Implementations can be swapped (e.g., Tesseract, Apple Vision, third-party SDKs).
protocol OCRServiceProtocol: AnyObject {

    /// Recognizes text from a given image.
    /// - Parameter image: The preprocessed image containing text to recognize.
    /// - Parameter completion: Called with the recognized string or an error.
    func recognizeText(from image: UIImage, completion: @escaping (Result<String, Error>) -> Void)

    /// The language(s) currently configured for recognition (e.g., "chi_sim", "eng").
    var recognitionLanguages: [String] { get set }
}

// MARK: - OCR Service Errors
enum OCRServiceError: LocalizedError {
    case imageTooSmall
    case recognitionFailed(String)
    case languageDataNotFound(String)
    case initializationFailed(String)

    var errorDescription: String? {
        switch self {
        case .imageTooSmall:
            return "图片尺寸过小，无法识别"
        case .recognitionFailed(let detail):
            return "文字识别失败：\(detail)"
        case .languageDataNotFound(let lang):
            return "未找到语言数据：\(lang)"
        case .initializationFailed(let detail):
            return "OCR 引擎初始化失败：\(detail)"
        }
    }
}
