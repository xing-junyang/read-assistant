import UIKit

// MARK: - Bailian (百联) OCR Service
/// OCR implementation using Alibaba Cloud Bailian multimodal model (Qwen-VL)
/// via OpenAI-compatible API.
///
/// ## Configuration
/// Set `apiKey` before use. The key can be obtained from the Bailian console:
/// https://bailian.console.aliyun.com
///
/// ## Model
/// Default: `qwen-vl-plus` (multimodal vision-language model).
/// For higher accuracy, change to `qwen-vl-max`.
///
/// ## API Format
/// Compatible with OpenAI Chat Completions API (vision).
/// Endpoint: `https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions`
final class BailianOCRService: OCRServiceProtocol {

    // MARK: - Configuration

    /// Shared default API key. Set this once at app startup (e.g., in AppDelegate)
    /// or read it from a secure source. All new BailianOCRService instances
    /// will pick up this value.
    ///
    /// Obtain from: https://bailian.console.aliyun.com → API-KEY 管理
    static var defaultAPIKey: String = "sk-1fb6a603205546358c1541c48ea579bd"

    /// Alibaba Cloud Bailian API Key. Must be set before calling `recognizeText`.
    /// Obtain from: https://bailian.console.aliyun.com → API-KEY 管理
    var apiKey: String

    /// Model name. Change this to use a different Bailian model.
    /// - `qwen-vl-plus`: Good balance of speed and accuracy (default)
    /// - `qwen-vl-max`: Best accuracy for complex documents
    var model: String

    /// Base URL for the OpenAI-compatible endpoint.
    /// Usually no need to change this.
    var baseURL: String

    /// Max image dimension before sending to API. Larger images consume more tokens.
    /// 2048 is a good balance between quality and cost.
    var maxImageDimension: CGFloat = 2048

    /// JPEG compression quality (0.0–1.0). Lower = smaller payload, faster.
    var jpegQuality: CGFloat = 0.85

    // MARK: - OCRServiceProtocol

    /// Language hints sent in the system prompt. Not used for model config.
    var recognitionLanguages: [String] = ["chinese", "english"]

    // MARK: - Init

    /// - Parameters:
    ///   - apiKey: Bailian API key. Defaults to the developer-overridden value, or the hardcoded default.
    ///   - model: Model name. Defaults to the developer-overridden value, or `qwen3-vl-plus`.
    ///   - baseURL: API base URL. Defaults to the developer-overridden value, or DashScope compatible-mode endpoint.
    init(apiKey: String = DeveloperSettingsManager.shared.effectiveAPIKey,
         model: String = DeveloperSettingsManager.shared.effectiveModel,
         baseURL: String = DeveloperSettingsManager.shared.effectiveBaseURL) {
        self.apiKey = apiKey
        self.model = model
        self.baseURL = baseURL
    }

    // MARK: - OCRServiceProtocol

    func recognizeText(from image: UIImage, completion: @escaping (Result<String, Error>) -> Void) {
        guard !apiKey.isEmpty else {
            DispatchQueue.main.async {
                completion(.failure(OCRServiceError.initializationFailed(
                    "请先设置 Bailian API Key。在代码中设置 BailianOCRService().apiKey")))
            }
            return
        }

        // Resize image for API efficiency
        let prepared = Self.prepareImageForAPI(image, maxDimension: maxImageDimension)

        guard let imageData = prepared.jpegData(compressionQuality: jpegQuality) else {
            DispatchQueue.main.async {
                completion(.failure(OCRServiceError.initializationFailed("无法转换图片为 JPEG 格式")))
            }
            return
        }

        let base64Image = imageData.base64EncodedString()
        let dataURI = "data:image/jpeg;base64,\(base64Image)"

        // Build the system prompt with language hints
        let langDesc = recognitionLanguages.joined(separator: "、")
        let systemPrompt = """
        你是一个精确的 OCR 文字提取助手。请**只输出**图片中的原始文字内容，严格保持原有格式、段落和换行。
        不要添加任何解释、注释或额外内容。不要输出"图片中包含"等引导语。
        图片可能包含的语言：\(langDesc)。
        """

        let requestBody: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": [
                    ["type": "image_url", "image_url": ["url": dataURI]],
                    ["type": "text", "text": "请提取图片中的所有文字。"]
                ]]
            ],
            "max_tokens": 4096,
            "temperature": 0.0
        ]

        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            DispatchQueue.main.async {
                completion(.failure(OCRServiceError.initializationFailed("无效的 API 地址")))
            }
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        } catch {
            DispatchQueue.main.async {
                completion(.failure(OCRServiceError.initializationFailed("请求序列化失败: \(error.localizedDescription)")))
            }
            return
        }

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            // Network error
            if let error = error {
                DispatchQueue.main.async {
                    completion(.failure(OCRServiceError.recognitionFailed("网络错误: \(error.localizedDescription)")))
                }
                return
            }

            // HTTP error
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode != 200 {
                let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                DispatchQueue.main.async {
                    completion(.failure(OCRServiceError.recognitionFailed(
                        "HTTP \(httpResponse.statusCode): \(body.prefix(200))")))
                }
                return
            }

            guard let data = data else {
                DispatchQueue.main.async {
                    completion(.failure(OCRServiceError.recognitionFailed("服务器无响应")))
                }
                return
            }

            // Parse OpenAI-compatible response
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                DispatchQueue.main.async {
                    let raw = String(data: data, encoding: .utf8) ?? "无法解析"
                    completion(.failure(OCRServiceError.recognitionFailed("响应解析失败: \(raw.prefix(200))")))
                }
                return
            }

            // Check for API-level error
            if let apiError = json["error"] as? [String: Any],
               let message = apiError["message"] as? String {
                DispatchQueue.main.async {
                    completion(.failure(OCRServiceError.recognitionFailed("API 错误: \(message)")))
                }
                return
            }

            // Extract text from choices[0].message.content
            if let choices = json["choices"] as? [[String: Any]],
               let firstChoice = choices.first,
               let message = firstChoice["message"] as? [String: Any],
               let content = message["content"] as? String {
                let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
                DispatchQueue.main.async {
                    if text.isEmpty {
                        completion(.failure(OCRServiceError.recognitionFailed("模型未返回文字内容")))
                    } else {
                        completion(.success(text))
                    }
                }
            } else {
                DispatchQueue.main.async {
                    let raw = String(data: data, encoding: .utf8) ?? "无法解析"
                    completion(.failure(OCRServiceError.recognitionFailed("响应格式异常: \(raw.prefix(200))")))
                }
            }
        }
        task.resume()
    }

    // MARK: - Image Preparation

    /// Resizes image to fit within `maxDimension` while maintaining aspect ratio.
    /// Uses UIGraphicsBeginImageContextWithOptions for 32 bpp output
    /// (safe for all iOS versions, including wide-gamut devices).
    private static func prepareImageForAPI(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        guard let cgImage = image.cgImage else { return image }

        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)

        let scale: CGFloat
        if width > maxDimension || height > maxDimension {
            scale = min(maxDimension / width, maxDimension / height)
        } else {
            scale = 1.0
        }

        guard scale < 1.0 else { return image }

        let newSize = CGSize(width: width * scale, height: height * scale)

        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        defer { UIGraphicsEndImageContext() }

        image.draw(in: CGRect(origin: .zero, size: newSize))

        return UIGraphicsGetImageFromCurrentImageContext() ?? image
    }
}
