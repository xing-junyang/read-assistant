import UIKit
import TesseractOCR

// MARK: - Tesseract OCR Service
/// OCR implementation using TesseractOCRiOS (CocoaPods).
///
/// Uses `G8Tesseract` directly instead of `G8RecognitionOperation` so the
/// engine mode can be set during initialization. Mirrors the exact call
/// sequence of `G8RecognitionOperation.main`:
///   1. analyseLayout() — page segmentation + orientation
///   2. recognize()    — text recognition
/// Both are required; skipping analyseLayout causes SIGABRT.
///
/// ## Image Format
/// Images are normalized to 32 bpp sRGB via UIGraphicsBeginImageContext.
/// Leptonica does NOT support 64 bpp (iOS wide gamut / HDR).
final class TesseractOCRService: OCRServiceProtocol {

    // MARK: - Properties
    var recognitionLanguages: [String] = ["eng"]  // 先用 eng 验证 Tesseract 本身是否正常

    /// Serial operation queue. Tesseract's C++ engine is not thread-safe.
    private let operationQueue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 1
        q.qualityOfService = .userInitiated
        return q
    }()

    // MARK: - OCRServiceProtocol

    func recognizeText(from image: UIImage, completion: @escaping (Result<String, Error>) -> Void) {
        // Step 0: Verify traineddata exists before touching C++ API.
        for lang in recognitionLanguages {
            guard Self.traineddataExists(for: lang) else {
                DispatchQueue.main.async {
                    completion(.failure(OCRServiceError.languageDataNotFound(
                        "找不到语言包 \(lang).traineddata。")))
                }
                return
            }
        }

        // Step 1: Resize if needed (safe UIGraphicsImageRenderer, not CGBitmapContext).
        let prepared = Self.prepareImageIfNeeded(image)
        let languageString = recognitionLanguages.joined(separator: "+")

        // Step 2: Create G8Tesseract with the correct engine mode.
        //         Using .tesseractOnly because this traineddata is legacy-only.
        guard let tesseract = G8Tesseract(language: languageString,
                                          engineMode: .tesseractOnly) else {
            DispatchQueue.main.async {
                completion(.failure(OCRServiceError.initializationFailed(
                    "无法初始化 Tesseract 引擎。")))
            }
            return
        }

        tesseract.pageSegmentationMode = .auto
        tesseract.image = prepared

        // Step 3: Run recognition on background queue.
        //         IMPORTANT: analyseLayout must be called before recognize,
        //         exactly as G8RecognitionOperation does internally.
        //         Skipping it causes SIGABRT in the legacy recognition pipeline.
        operationQueue.addOperation {
            tesseract.analyseLayout()
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

    // MARK: - Traineddata Verification
    private static func traineddataExists(for language: String) -> Bool {
        // Check tessdata/ subfolder (folder reference).
        if let url = Bundle.main.url(forResource: language,
                                      withExtension: "traineddata",
                                      subdirectory: "tessdata") {
            return (try? url.checkResourceIsReachable()) ?? false
        }
        // Check bundle root (individual file).
        if let url = Bundle.main.url(forResource: language,
                                      withExtension: "traineddata") {
            return (try? url.checkResourceIsReachable()) ?? false
        }
        return false
    }

    // MARK: - Image Preparation
    /// Resizes and converts the image to 32 bpp sRGB — the only format Tesseract
    /// reliably accepts. Leptonica crashes on 64 bpp images (iOS 14+ wide gamut).
    private static let maxImageDimension: CGFloat = 2048

    private static func prepareImageIfNeeded(_ image: UIImage) -> UIImage {
        guard let cgImage = image.cgImage else { return image }

        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)

        let scale: CGFloat
        if width > maxImageDimension || height > maxImageDimension {
            scale = min(maxImageDimension / width, maxImageDimension / height)
        } else {
            scale = 1.0
        }
        let newSize = CGSize(width: width * scale, height: height * scale)

        // UIGraphicsBeginImageContextWithOptions ALWAYS creates a
        // standard ARGB8888 (32 bpp) context, compatible with Leptonica.
        // Never use UIGraphicsImageRenderer here — it can produce 64 bpp.
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        defer { UIGraphicsEndImageContext() }
        guard let ctx = UIGraphicsGetCurrentContext() else { return image }

        // Fill white background for non-opaque images.
        ctx.setFillColor(UIColor.white.cgColor)
        ctx.fill(CGRect(origin: .zero, size: newSize))

        image.draw(in: CGRect(origin: .zero, size: newSize))

        guard let result = UIGraphicsGetImageFromCurrentImageContext() else {
            return image
        }

        // Sanity check: log bpp for debugging.
        if let cg = result.cgImage {
            let bpp = cg.bitsPerPixel
            if bpp != 32 && bpp != 24 {
                NSLog("[TesseractOCRService] ⚠️ Image bpp = \(bpp), expected 32. Recognition may fail.")
            }
        }

        return result
    }
}
