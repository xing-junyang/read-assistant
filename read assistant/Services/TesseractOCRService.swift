import UIKit
import CoreImage
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

    // MARK: - OCRServiceProtocol

    func recognizeText(from image: UIImage, completion: @escaping (Result<String, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let languageString = self.recognitionLanguages.joined(separator: "+")

            guard let tesseract = G8Tesseract(language: languageString) else {
                DispatchQueue.main.async {
                    let lang = self.recognitionLanguages.joined(separator: ", ")
                    completion(.failure(OCRServiceError.initializationFailed(
                        "无法初始化 Tesseract 引擎。请确认 \(lang) 语言包已添加到 Bundle。")))
                }
                return
            }

            // Configure engine
            tesseract.engineMode = .tesseractOnly
            tesseract.pageSegmentationMode = .auto

            // Preprocess and set image
            tesseract.image = self.preprocessImage(image) ?? image

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

    // MARK: - Image Preprocessing
    /// Converts the image to grayscale and boosts contrast for better OCR accuracy.
    /// CIColorControls (iOS 5+) is fully available on iOS 10.
    private func preprocessImage(_ image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let ciImage = CIImage(cgImage: cgImage)

        guard let grayFilter = CIFilter(name: "CIColorControls") else { return image }
        grayFilter.setValue(ciImage, forKey: kCIInputImageKey)
        grayFilter.setValue(0.0, forKey: kCIInputSaturationKey)
        grayFilter.setValue(1.15, forKey: kCIInputContrastKey)

        guard let grayImage = grayFilter.outputImage else { return image }

        let context = CIContext(options: nil)
        guard let outputCG = context.createCGImage(grayImage, from: grayImage.extent) else {
            return image
        }

        return UIImage(cgImage: outputCG)
    }
}
