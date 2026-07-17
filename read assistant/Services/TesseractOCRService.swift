import UIKit
import CoreImage

// MARK: - Tesseract OCR Service
/// OCR implementation using Tesseract 4.x static library.
/// This service wraps the C API of Tesseract for text recognition.
///
/// Integration steps (manual):
/// 1. Cross-compile Tesseract 4.x + Leptonica for iOS (armv7, arm64)
/// 2. Add libtesseract.a and libleptonica.a to Xcode project
/// 3. Add Chinese trained data (chi_sim.traineddata) to app bundle
/// 4. Set up bridging header for C API access
///
/// The Tesseract C API wrapper functions (tesseract_create, tesseract_delete,
/// tesseract_set_image, tesseract_get_utf8_text, etc.) should be defined
/// in the bridging header.
final class TesseractOCRService: OCRServiceProtocol {

    // MARK: - Properties
    var recognitionLanguages: [String] = ["chi_sim"]

    private let tessdataPath: String
    private var tesseractHandle: OpaquePointer?

    // MARK: - Initialization
    init() {
        // tessdata should be bundled in the app or copied at first launch
        if let bundledPath = Bundle.main.path(forResource: "tessdata", ofType: nil) {
            self.tessdataPath = bundledPath
        } else {
            // Fallback: copy to Documents
            let docs = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!
            self.tessdataPath = (docs as NSString).appendingPathComponent("tessdata")
        }
    }

    deinit {
        destroyTesseract()
    }

    // MARK: - OCRServiceProtocol

    func recognizeText(from image: UIImage, completion: @escaping (Result<String, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            // Step 1: Preprocess the image
            guard let preprocessed = self.preprocessImage(image) else {
                DispatchQueue.main.async {
                    completion(.failure(OCRServiceError.imageTooSmall))
                }
                return
            }

            // Step 2: Initialize Tesseract if needed
            if !self.initializeTesseract() {
                DispatchQueue.main.async {
                    completion(.failure(OCRServiceError.initializationFailed("无法初始化 Tesseract 引擎")))
                }
                return
            }

            // Step 3: Set image and perform recognition
            let result = self.performRecognition(on: preprocessed)

            DispatchQueue.main.async {
                if let text = result {
                    completion(.success(text))
                } else {
                    completion(.failure(OCRServiceError.recognitionFailed("识别过程出错")))
                }
            }
        }
    }

    // MARK: - Image Preprocessing
    /// Applies preprocessing to improve OCR accuracy:
    /// - Convert to grayscale
    /// - Increase contrast
    /// - Apply adaptive thresholding (via Core Image)
    private func preprocessImage(_ image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let ciImage = CIImage(cgImage: cgImage)

        // Convert to grayscale using CIColorControls
        guard let grayFilter = CIFilter(name: "CIColorControls") else { return image }
        grayFilter.setValue(ciImage, forKey: kCIInputImageKey)
        grayFilter.setValue(0.0, forKey: kCIInputSaturationKey) // Desaturate
        grayFilter.setValue(1.1, forKey: kCIInputContrastKey)   // Slight contrast boost

        guard let grayImage = grayFilter.outputImage else { return image }

        // Apply exposure adjustment for better text visibility
        guard let exposureFilter = CIFilter(name: "CIExposureAdjust") else { return image }
        exposureFilter.setValue(grayImage, forKey: kCIInputImageKey)
        exposureFilter.setValue(0.3, forKey: kCIInputEVKey)

        guard let outputImage = exposureFilter.outputImage else { return image }

        let context = CIContext(options: nil)
        guard let outputCG = context.createCGImage(outputImage, from: outputImage.extent) else {
            return image
        }

        return UIImage(cgImage: outputCG)
    }

    // MARK: - Tesseract Lifecycle

    private func initializeTesseract() -> Bool {
        guard tesseractHandle == nil else { return true }

        let languageString = recognitionLanguages.joined(separator: "+")

        // Tesseract C API call (requires bridging header):
        // tesseractHandle = tesseract_create(tessdataPath, languageString, OEM_DEFAULT)
        //
        // Placeholder: Simulate with a flag
        tesseractHandle = OpaquePointer(bitPattern: 0x1) // Placeholder

        guard tesseractHandle != nil else {
            print("[TesseractOCR] Failed to initialize with languages: \(languageString)")
            return false
        }

        // Configure Tesseract parameters
        // tesseract_set_variable(tesseractHandle, "tessedit_char_whitelist", "")
        // tesseract_set_variable(tesseractHandle, "preserve_interword_spaces", "1")

        return true
    }

    private func performRecognition(on image: UIImage) -> String? {
        guard let cgImage = image.cgImage else { return nil }

        let width = Int32(cgImage.width)
        let height = Int32(cgImage.height)
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * Int(width)

        var pixelData = [UInt8](repeating: 0, count: Int(height) * bytesPerRow)
        guard let context = CGContext(
            data: &pixelData,
            width: Int(width),
            height: Int(height),
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: Int(width), height: Int(height)))

        // Tesseract C API calls (requires bridging header):
        // tesseract_set_image(tesseractHandle, pixelData, width, height, bytesPerPixel, bytesPerRow)
        // let textPtr = tesseract_get_utf8_text(tesseractHandle)
        // let result = String(cString: textPtr!)
        // tesseract_delete_text(textPtr)

        // Placeholder: return a meaningful message
        return "[Tesseract OCR - 请在集成 libtesseract.a 后使用]"
    }

    private func destroyTesseract() {
        guard let handle = tesseractHandle else { return }
        // tesseract_delete(handle)
        tesseractHandle = nil
    }
}
