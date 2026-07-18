import UIKit
import TesseractOCR

// MARK: - Tesseract OCR Service
/// OCR implementation using TesseractOCRiOS (CocoaPods).
///
/// Integration steps:
/// 1. Add `pod 'TesseractOCRiOS', '~> 4.0.0'` to Podfile, then run `pod install`
/// 2. Download `chi_sim.traineddata` from https://github.com/tesseract-ocr/tessdata
/// 3. Drag the .traineddata file into Xcode (Copy Bundle Resources)
///
/// The G8Tesseract class comes from the TesseractOCRiOS pod and wraps
/// the Tesseract 4.x C++ engine for iOS.
final class TesseractOCRService: OCRServiceProtocol {

    // MARK: - Properties
    var recognitionLanguages: [String] = ["chi_sim"]

    /// Maximum pixel dimension for images passed to Tesseract.
    /// Full camera-resolution photos (4032×3024) are downscaled to avoid
    /// excessive memory usage that causes EXC_BAD_ACCESS on mobile devices.
    private static let maxImageDimension: CGFloat = 2048

    /// Serial queue to prevent concurrent Tesseract operations,
    /// since the underlying C++ engine and its global caches are not thread-safe.
    private let recognitionQueue = DispatchQueue(label: "com.readassistant.tesseract",
                                                  qos: .userInitiated)

    /// Reuse a single G8Tesseract instance across recognitions.
    /// Creating a new instance each time calls Init() repeatedly,
    /// which corrupts Tesseract's global language-data caches and
    /// causes EXC_BAD_ACCESS on the second recognition.
    private var tesseract: G8Tesseract?

    // MARK: - OCRServiceProtocol

    func recognizeText(from image: UIImage, completion: @escaping (Result<String, Error>) -> Void) {
        // Prep image on calling thread: downscale + stable bitmap copy.
        // This keeps memory manageable and ensures data independence.
        guard let prepared = Self.prepareImage(image) else {
            DispatchQueue.main.async {
                completion(.failure(OCRServiceError.recognitionFailed("图片数据无效")))
            }
            return
        }

        recognitionQueue.async { [weak self] in
            guard let self = self else { return }

            // Reuse existing instance or create one on first use.
            // Repeated Init() calls across separate instances corrupt
            // Tesseract's global caches.
            let tesseract: G8Tesseract
            if let existing = self.tesseract {
                tesseract = existing
            } else {
                // Clear any stale global caches left by a previous instance
                // (e.g. if the user dismissed and reopened the OCR screen).
                G8Tesseract.clearCache()

                let languageString = self.recognitionLanguages.joined(separator: "+")
                guard let newInstance = G8Tesseract(language: languageString) else {
                    DispatchQueue.main.async {
                        let lang = self.recognitionLanguages.joined(separator: ", ")
                        completion(.failure(OCRServiceError.initializationFailed(
                            "无法初始化 Tesseract 引擎。请确认 \(lang) 语言包已添加到 Bundle。")))
                    }
                    return
                }
                newInstance.engineMode = .tesseractOnly
                newInstance.pageSegmentationMode = .auto
                self.tesseract = newInstance
                tesseract = newInstance
            }

            tesseract.image = prepared

            // Perform recognition
            tesseract.recognize()

            let text = tesseract.recognizedText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            DispatchQueue.main.async {
                if text.isEmpty {
                    completion(.failure(OCRServiceError.recognitionFailed("未识别到文字")))
                } else {
                    completion(.success(text))
                }
            }
        }
    }

    // MARK: - Image Preparation
    /// Downscales (if needed) and creates a self-contained bitmap copy of the image.
    /// Full camera-resolution photos are downscaled to prevent excessive memory usage
    /// (Tesseract internally copies the image multiple times, easily exceeding 150MB).
    private static func prepareImage(_ image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }

        let origWidth = CGFloat(cgImage.width)
        let origHeight = CGFloat(cgImage.height)

        // Downscale if either dimension exceeds the limit
        let scale: CGFloat
        if origWidth > maxImageDimension || origHeight > maxImageDimension {
            scale = min(maxImageDimension / origWidth, maxImageDimension / origHeight)
        } else {
            scale = 1.0
        }

        let targetWidth = origWidth * scale
        let targetHeight = origHeight * scale

        UIGraphicsBeginImageContextWithOptions(
            CGSize(width: targetWidth, height: targetHeight),
            false, 1.0
        )
        defer { UIGraphicsEndImageContext() }

        guard let context = UIGraphicsGetCurrentContext() else { return nil }
        context.interpolationQuality = .high
        image.draw(in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))

        return UIGraphicsGetImageFromCurrentImageContext()
    }
}
