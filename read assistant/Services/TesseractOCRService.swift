import UIKit
import TesseractOCR

// MARK: - Tesseract OCR Service
/// OCR implementation using TesseractOCRiOS (CocoaPods).
///
/// Uses G8RecognitionOperation (NSOperation-based) per the library's
/// recommended pattern. This avoids thread-safety pitfalls and
/// memory-management issues that arise from manually reusing G8Tesseract
/// instances across multiple recognitions.
final class TesseractOCRService: OCRServiceProtocol {

    // MARK: - Properties
    var recognitionLanguages: [String] = ["chi_sim"]

    /// Maximum pixel dimension for images passed to Tesseract.
    /// Full camera-resolution photos (4032×3024) are downscaled to avoid
    /// excessive memory usage that causes EXC_BAD_ACCESS on mobile devices.
    private static let maxImageDimension: CGFloat = 2048

    /// Serial operation queue for recognition operations.
    /// Tesseract's underlying C++ engine and global caches are not
    /// thread-safe, so we process one recognition at a time.
    private let operationQueue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 1
        q.qualityOfService = .userInitiated
        return q
    }()

    // MARK: - OCRServiceProtocol

    func recognizeText(from image: UIImage, completion: @escaping (Result<String, Error>) -> Void) {
        // Prep image on calling thread: downscale + stable bitmap copy.
        guard let prepared = Self.prepareImage(image) else {
            DispatchQueue.main.async {
                completion(.failure(OCRServiceError.recognitionFailed("图片数据无效")))
            }
            return
        }

        // G8RecognitionOperation creates its own G8Tesseract internally,
        // avoiding lifetime / cache-corruption issues from manual reuse.
        // ⚠️ The library does NOT return nil when Tesseract init fails —
        //    operation.tesseract will be nil instead. We must check for that.
        let languageString = recognitionLanguages.joined(separator: "+")
        guard let operation = G8RecognitionOperation(language: languageString),
              operation.tesseract != nil else {
            DispatchQueue.main.async {
                let lang = self.recognitionLanguages.joined(separator: ", ")
                completion(.failure(OCRServiceError.initializationFailed(
                    "无法初始化 Tesseract 引擎。请确认 \(lang) 语言包已添加到 Bundle。")))
            }
            return
        }

        operation.tesseract.engineMode = .tesseractOnly
        operation.tesseract.pageSegmentationMode = .auto
        operation.tesseract.image = prepared

        // Called on main thread when recognition finishes.
        operation.recognitionCompleteBlock = { tesseract in
            let text = tesseract?.recognizedText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if text.isEmpty {
                completion(.failure(OCRServiceError.recognitionFailed("未识别到文字")))
            } else {
                completion(.success(text))
            }
        }

        operationQueue.addOperation(operation)
    }

    // MARK: - Image Preparation
    /// Downscales (if needed) and creates a self-contained grayscale bitmap
    /// copy of the image. Using 8-bit gray avoids alpha-channel ambiguities
    /// in G8Tesseract.pixForImage:.
    private static func prepareImage(_ image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }

        let origWidth = CGFloat(cgImage.width)
        let origHeight = CGFloat(cgImage.height)

        let scale: CGFloat
        if origWidth > maxImageDimension || origHeight > maxImageDimension {
            scale = min(maxImageDimension / origWidth, maxImageDimension / origHeight)
        } else {
            scale = 1.0
        }

        let targetWidth = Int(origWidth * scale)
        let targetHeight = Int(origHeight * scale)

        // Create an 8-bit grayscale context (no alpha).
        // This avoids the complex 32-bit byte-swizzling in pixForImage:,
        // going through the simple 8-bit copy path instead.
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let context = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: targetWidth,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))

        guard let outputCGImage = context.makeImage() else { return nil }
        return UIImage(cgImage: outputCGImage)
    }
}
