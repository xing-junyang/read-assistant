import UIKit
import AVFoundation
import CoreImage

// MARK: - OCR Scan View Controller
/// Allows users to capture a document photo, manually mark four corners
/// for perspective correction, and then perform OCR.
final class OCRScanViewController: UIViewController {

    // MARK: - Properties
    /// Pluggable OCR service — uses Bailian multimodal model by default.
    /// Set `ocrService.apiKey` before presenting this view controller.
    var ocrService: OCRServiceProtocol = BailianOCRService()
    var onTextRecognized: ((String) -> Void)?

    // Camera
    private var captureSession: AVCaptureSession?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var stillImageOutput: AVCaptureStillImageOutput?
    private var capturedImage: UIImage?
    private var isCapturing = false

    // Corner marking
    private var corners: [CGPoint] = []
    private var cornerMarkers: [UIView] = []
    private var isMarkingCorners = false
    private let maxCorners = 4

    /// Shape layer that draws lines connecting the marked corners
    private let quadShapeLayer = CAShapeLayer()

    // Image view for captured photo
    private let imageView = UIImageView()
    private let overlayView = UIView()

    // Buttons
    private let captureButton = UIButton(type: .system)
    private let retakeButton = UIButton(type: .system)
    private let recognizeButton = UIButton(type: .system)
    private let clearCornersButton = UIButton(type: .system)

    private let instructionLabel = UILabel()
    private let activityIndicator = UIActivityIndicatorView(style: .whiteLarge)

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupCamera()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        captureSession?.stopRunning()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    // MARK: - UI Setup
    private func setupUI() {
        view.backgroundColor = .black
        title = "拍照识别"

        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelTapped))

        // Image view (for captured photo)
        imageView.contentMode = .scaleAspectFit
        imageView.backgroundColor = .black
        imageView.isHidden = true
        imageView.isUserInteractionEnabled = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(imageView)

        // Overlay for corner markers
        overlayView.backgroundColor = .clear
        overlayView.isHidden = true
        overlayView.isUserInteractionEnabled = true
        overlayView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(overlayView)

        // Shape layer for drawing the quad outline
        quadShapeLayer.fillColor = UIColor.accent.withAlphaComponent(0.1).cgColor
        quadShapeLayer.strokeColor = UIColor.accent.cgColor
        quadShapeLayer.lineWidth = 2.5
        quadShapeLayer.lineDashPattern = [6, 3]
        overlayView.layer.addSublayer(quadShapeLayer)

        // Tap gesture for marking corners
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        overlayView.addGestureRecognizer(tapGesture)

        // Instruction
        instructionLabel.text = "将文档对准取景框，然后拍照"
        instructionLabel.textColor = .white
        instructionLabel.textAlignment = .center
        instructionLabel.font = UIFont.systemFont(ofSize: 14)
        instructionLabel.numberOfLines = 0
        instructionLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(instructionLabel)

        // Capture button
        captureButton.setTitle("📷 拍照", for: .normal)
        captureButton.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        captureButton.setTitleColor(.white, for: .normal)
        captureButton.backgroundColor = .primary
        captureButton.layer.cornerRadius = 30
        captureButton.addTarget(self, action: #selector(captureTapped), for: .touchUpInside)
        captureButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(captureButton)

        // Retake button
        retakeButton.setTitle("🔄 重拍", for: .normal)
        retakeButton.setTitleColor(.white, for: .normal)
        retakeButton.backgroundColor = UIColor(white: 0.3, alpha: 1.0)
        retakeButton.layer.cornerRadius = 22
        retakeButton.isHidden = true
        retakeButton.addTarget(self, action: #selector(retakeTapped), for: .touchUpInside)
        retakeButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(retakeButton)

        // Recognize button
        recognizeButton.setTitle("🔍 开始识别", for: .normal)
        recognizeButton.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        recognizeButton.setTitleColor(.white, for: .normal)
        recognizeButton.backgroundColor = .successGreen
        recognizeButton.layer.cornerRadius = 22
        recognizeButton.isHidden = true
        recognizeButton.addTarget(self, action: #selector(recognizeTapped), for: .touchUpInside)
        recognizeButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(recognizeButton)

        // Clear corners
        clearCornersButton.setTitle("清除标记", for: .normal)
        clearCornersButton.setTitleColor(.white, for: .normal)
        clearCornersButton.titleLabel?.font = UIFont.systemFont(ofSize: 13)
        clearCornersButton.backgroundColor = UIColor(white: 0.3, alpha: 1.0)
        clearCornersButton.layer.cornerRadius = 16
        clearCornersButton.isHidden = true
        clearCornersButton.addTarget(self, action: #selector(clearCornersTapped), for: .touchUpInside)
        clearCornersButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(clearCornersButton)

        // Activity indicator
        activityIndicator.color = .white
        activityIndicator.hidesWhenStopped = true
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(activityIndicator)

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: compatSafeAreaTop),
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            overlayView.topAnchor.constraint(equalTo: imageView.topAnchor),
            overlayView.leadingAnchor.constraint(equalTo: imageView.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: imageView.trailingAnchor),
            overlayView.bottomAnchor.constraint(equalTo: imageView.bottomAnchor),

            instructionLabel.bottomAnchor.constraint(equalTo: captureButton.topAnchor, constant: -16),
            instructionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            instructionLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            captureButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            captureButton.bottomAnchor.constraint(equalTo: compatSafeAreaBottom, constant: -24),
            captureButton.widthAnchor.constraint(equalToConstant: 150),
            captureButton.heightAnchor.constraint(equalToConstant: 60),

            retakeButton.centerYAnchor.constraint(equalTo: captureButton.centerYAnchor),
            retakeButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            retakeButton.widthAnchor.constraint(equalToConstant: 80),
            retakeButton.heightAnchor.constraint(equalToConstant: 44),

            recognizeButton.centerYAnchor.constraint(equalTo: captureButton.centerYAnchor),
            recognizeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            recognizeButton.widthAnchor.constraint(equalToConstant: 120),
            recognizeButton.heightAnchor.constraint(equalToConstant: 44),

            clearCornersButton.topAnchor.constraint(equalTo: imageView.topAnchor, constant: 12),
            clearCornersButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            clearCornersButton.widthAnchor.constraint(equalToConstant: 80),
            clearCornersButton.heightAnchor.constraint(equalToConstant: 32),

            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    // MARK: - Camera Setup
    private func setupCamera() {
        let session = AVCaptureSession()
        session.sessionPreset = .photo

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else {
            instructionLabel.text = "无法访问相机"
            return
        }

        if session.canAddInput(input) {
            session.addInput(input)
        }

        // Still image output for capturing photos (iOS 10 compatible)
        let output = AVCaptureStillImageOutput()
        output.outputSettings = [AVVideoCodecKey: AVVideoCodecJPEG]
        if session.canAddOutput(output) {
            session.addOutput(output)
            self.stillImageOutput = output
        }

        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer.insertSublayer(previewLayer, at: 0)
        self.previewLayer = previewLayer
        self.captureSession = session

        DispatchQueue.global(qos: .userInitiated).async {
            session.startRunning()
        }
    }

    // MARK: - Capture
    @objc private func captureTapped() {
        guard !isCapturing,
              let stillImageOutput = stillImageOutput,
              let connection = stillImageOutput.connection(with: .video) else { return }

        isCapturing = true
        stillImageOutput.captureStillImageAsynchronously(from: connection) { [weak self] buffer, error in
            if let error = error {
                DispatchQueue.main.async {
                    self?.isCapturing = false
                    self?.showAlert(title: "拍摄失败", message: error.localizedDescription)
                }
                return
            }

            guard let buffer = buffer,
                  let imageData = AVCaptureStillImageOutput.jpegStillImageNSDataRepresentation(buffer),
                  let image = UIImage(data: imageData) else {
                DispatchQueue.main.async {
                    self?.isCapturing = false
                    self?.showAlert(title: "拍摄失败", message: "无法获取照片数据")
                }
                return
            }

            DispatchQueue.main.async {
                self?.captureSession?.stopRunning()
                self?.isCapturing = false
                self?.showCapturedImage(image)
            }
        }
    }

    private func showCapturedImage(_ image: UIImage) {
        capturedImage = image
        previewLayer?.isHidden = true
        imageView.image = image
        imageView.isHidden = false
        overlayView.isHidden = false

        captureButton.isHidden = true
        instructionLabel.isHidden = true
        retakeButton.isHidden = false
        recognizeButton.isHidden = false
        clearCornersButton.isHidden = false

        instructionLabel.text = "请点击文档的四个角（左上、右上、右下、左下）进行标记"
        instructionLabel.isHidden = false
        instructionLabel.textColor = .white
    }

    @objc private func retakeTapped() {
        capturedImage = nil
        corners.removeAll()
        clearCornerMarkers()
        quadShapeLayer.path = nil

        imageView.image = nil
        imageView.isHidden = true
        overlayView.isHidden = true
        previewLayer?.isHidden = false

        captureButton.isHidden = false
        instructionLabel.isHidden = false
        retakeButton.isHidden = true
        recognizeButton.isHidden = true
        clearCornersButton.isHidden = true

        instructionLabel.text = "将文档对准取景框，然后拍照"

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession?.startRunning()
        }
    }

    // MARK: - Corner Marking
    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard corners.count < maxCorners else { return }

        let point = gesture.location(in: overlayView)
        corners.append(point)
        addCornerMarker(at: point, index: corners.count - 1)
        updateQuadPath()

        if corners.count == maxCorners {
            instructionLabel.text = "四个角标记完成，点击「开始识别」或继续调整"
            recognizeButton.isEnabled = true
        } else {
            let labels = ["左上角", "右上角", "右下角", "左下角"]
            instructionLabel.text = "已标记 \(labels[corners.count - 1])，请点击下一个角"
        }
    }

    private func updateQuadPath() {
        guard corners.count >= 2 else {
            quadShapeLayer.path = nil
            return
        }

        let path = UIBezierPath()
        path.move(to: corners[0])
        for i in 1..<corners.count {
            path.addLine(to: corners[i])
        }
        // If we have all 4 corners, close the path
        if corners.count == 4 {
            path.addLine(to: corners[0])
            path.close()
        }
        quadShapeLayer.path = path.cgPath
    }

    private func addCornerMarker(at point: CGPoint, index: Int) {
        let marker = UIView(frame: CGRect(x: point.x - 12, y: point.y - 12, width: 24, height: 24))
        marker.backgroundColor = .accent
        marker.layer.cornerRadius = 12
        marker.layer.borderColor = UIColor.white.cgColor
        marker.layer.borderWidth = 2
        marker.tag = index

        let label = UILabel(frame: marker.bounds)
        label.text = "\(index + 1)"
        label.textColor = .white
        label.font = UIFont.systemFont(ofSize: 11, weight: .bold)
        label.textAlignment = .center
        marker.addSubview(label)

        overlayView.addSubview(marker)
        cornerMarkers.append(marker)
    }

    private func clearCornerMarkers() {
        cornerMarkers.forEach { $0.removeFromSuperview() }
        cornerMarkers.removeAll()
    }

    @objc private func clearCornersTapped() {
        corners.removeAll()
        clearCornerMarkers()
        quadShapeLayer.path = nil
        instructionLabel.text = "请点击文档的四个角（左上、右上、右下、左下）进行标记"
        recognizeButton.isEnabled = false
    }

    // MARK: - Recognition
    @objc private func recognizeTapped() {
        guard let image = capturedImage, corners.count == maxCorners else {
            showAlert(title: "提示", message: "请先标记文档的四个角")
            return
        }

        // Push to preview controller for draggable corner adjustment & confirmation.
        // corners are in overlayView coordinate space — the preview controller uses
        // the same scaleAspectFit layout, so coordinates are compatible.
        let previewVC = ImageCropPreviewViewController(image: image, corners: corners)
        previewVC.onCancel = { [weak self] in
            self?.navigationController?.popViewController(animated: true)
            self?.recognizeButton.isEnabled = true
            self?.instructionLabel.text = "四个角标记完成，点击「开始识别」"
        }
        previewVC.onConfirm = { [weak self] correctedImage in
            self?.navigationController?.popViewController(animated: true)
            self?.performOCR(on: correctedImage)
        }
        recognizeButton.isEnabled = false
        navigationController?.pushViewController(previewVC, animated: true)
    }

    private func performOCR(on image: UIImage) {
        activityIndicator.startAnimating()
        instructionLabel.text = "正在识别..."

        ocrService.recognizeText(from: image) { [weak self] result in
            self?.activityIndicator.stopAnimating()

            switch result {
            case .success(let text):
                self?.onTextRecognized?(text)
                self?.dismiss(animated: true)
            case .failure(let error):
                self?.showAlert(title: "识别失败", message: error.localizedDescription)
                self?.recognizeButton.isEnabled = true
                self?.instructionLabel.text = "识别失败，请重试"
            }
        }
    }

    // MARK: - Perspective Correction
    /// Applies perspective correction to warp the quadrilateral defined by corners
    /// into a rectangle using Core Image.
    private func performPerspectiveCorrection(on image: UIImage, corners: [CGPoint]) -> UIImage? {
        guard let ciImage = CIImage(image: image) else { return nil }
        guard corners.count == 4 else { return nil }

        // Convert UIKit coords (origin top-left) to Core Image coords (origin bottom-left)
        let imageHeight = ciImage.extent.height
        let imgSize = image.size

        // Scale normalized corner positions to image coordinates
        let scaledCorners = corners.map { point -> CGPoint in
            let normalizedX = point.x / overlayView.bounds.width * imgSize.width
            let normalizedY = point.y / overlayView.bounds.height * imgSize.height
            return CGPoint(x: normalizedX, y: imageHeight - normalizedY)
        }

        // Sort corners: topLeft, topRight, bottomRight, bottomLeft
        let sorted = sortCorners(scaledCorners)

        guard let filter = CIFilter(name: "CIPerspectiveCorrection") else { return nil }
        filter.setValue(ciImage, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgPoint: sorted[0]), forKey: "inputTopLeft")
        filter.setValue(CIVector(cgPoint: sorted[1]), forKey: "inputTopRight")
        filter.setValue(CIVector(cgPoint: sorted[2]), forKey: "inputBottomRight")
        filter.setValue(CIVector(cgPoint: sorted[3]), forKey: "inputBottomLeft")

        guard let outputImage = filter.outputImage else { return nil }

        let context = CIContext(options: nil)
        guard let outputCG = context.createCGImage(outputImage, from: outputImage.extent) else {
            return nil
        }

        return UIImage(cgImage: outputCG)
    }

    /// Sorts four corners into: topLeft, topRight, bottomRight, bottomLeft order.
    private func sortCorners(_ corners: [CGPoint]) -> [CGPoint] {
        // Sort by y (top to bottom)
        let sortedByY = corners.sorted { $0.y < $1.y }

        // Top two sorted by x (left to right)
        let topTwo = [sortedByY[0], sortedByY[1]].sorted { $0.x < $1.x }
        let topLeft = topTwo[0]
        let topRight = topTwo[1]

        // Bottom two sorted by x (left to right)
        let bottomTwo = [sortedByY[2], sortedByY[3]].sorted { $0.x < $1.x }
        let bottomLeft = bottomTwo[0]
        let bottomRight = bottomTwo[1]

        return [topLeft, topRight, bottomRight, bottomLeft]
    }

    // MARK: - Actions
    @objc private func cancelTapped() {
        dismiss(animated: true)
    }
}
