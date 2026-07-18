import UIKit

// MARK: - Image Crop Preview View Controller
/// Shows the captured photo with a draggable four-corner crop overlay.
/// The user can adjust corners, preview the perspective-corrected result,
/// then confirm or go back.
final class ImageCropPreviewViewController: UIViewController {

    // MARK: - Callbacks
    /// Called when user confirms: provides the perspective-corrected UIImage.
    var onConfirm: ((UIImage) -> Void)?
    /// Called when user taps back.
    var onCancel: (() -> Void)?

    // MARK: - Input
    /// The original captured image
    private let sourceImage: UIImage
    /// Initial corner positions (in imageView coordinate space)
    private var initialCorners: [CGPoint]

    // MARK: - Subviews
    private let imageView = UIImageView()
    private let cropOverlay = CropOverlayView()
    private let instructionLabel = UILabel()
    private let previewButton = UIButton(type: .system)
    private let confirmButton = UIButton(type: .system)
    private let backButton = UIButton(type: .system)
    private let resetButton = UIButton(type: .system)
    private let activityIndicator = UIActivityIndicatorView(style: .whiteLarge)

    /// Small inset view showing the perspective-corrected preview
    private let previewInsetView = UIView()
    private let previewInsetImageView = UIImageView()
    private let previewInsetLabel = UILabel()

    /// Whether we're currently showing the corrected preview
    private var isShowingCorrectedPreview = false

    // MARK: - Init
    init(image: UIImage, corners: [CGPoint]) {
        self.sourceImage = image
        self.initialCorners = corners
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupCorners()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Defer corner setup until bounds are finalized (safe area may not be
        // available in viewDidLoad). Only set once to avoid resetting user drags.
        if cropOverlay.corners.isEmpty && !initialCorners.isEmpty {
            cropOverlay.setCorners(initialCorners)
        } else if cropOverlay.corners.isEmpty && initialCorners.isEmpty {
            setupDefaultCorners()
        }
    }

    // MARK: - UI Setup
    private func setupUI() {
        view.backgroundColor = .black
        title = "调整选区"

        // --- Image View ---
        imageView.contentMode = .scaleAspectFit
        imageView.image = sourceImage
        imageView.backgroundColor = .black
        imageView.isUserInteractionEnabled = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(imageView)

        // --- Crop Overlay ---
        cropOverlay.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cropOverlay)

        // --- Instruction ---
        instructionLabel.text = "拖动四个角标记文档区域"
        instructionLabel.textColor = .white
        instructionLabel.textAlignment = .center
        instructionLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        instructionLabel.numberOfLines = 2
        instructionLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(instructionLabel)

        // --- Preview Inset (small corrected preview) ---
        setupPreviewInset()

        // --- Buttons ---
        backButton.setTitle("← 返回", for: .normal)
        backButton.titleLabel?.font = UIFont.systemFont(ofSize: 15, weight: .medium)
        backButton.setTitleColor(.white, for: .normal)
        backButton.backgroundColor = UIColor(white: 0.25, alpha: 0.9)
        backButton.layer.cornerRadius = 22
        backButton.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        backButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(backButton)

        resetButton.setTitle("↺ 重置", for: .normal)
        resetButton.titleLabel?.font = UIFont.systemFont(ofSize: 13)
        resetButton.setTitleColor(.white, for: .normal)
        resetButton.backgroundColor = UIColor(white: 0.25, alpha: 0.9)
        resetButton.layer.cornerRadius = 18
        resetButton.addTarget(self, action: #selector(resetTapped), for: .touchUpInside)
        resetButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(resetButton)

        previewButton.setTitle("👁 预览校正", for: .normal)
        previewButton.titleLabel?.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        previewButton.setTitleColor(.white, for: .normal)
        previewButton.backgroundColor = .accent
        previewButton.layer.cornerRadius = 22
        previewButton.addTarget(self, action: #selector(previewTapped), for: .touchUpInside)
        previewButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(previewButton)

        confirmButton.setTitle("✓ 确认", for: .normal)
        confirmButton.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: .bold)
        confirmButton.setTitleColor(.white, for: .normal)
        confirmButton.backgroundColor = .successGreen
        confirmButton.layer.cornerRadius = 24
        confirmButton.addTarget(self, action: #selector(confirmTapped), for: .touchUpInside)
        confirmButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(confirmButton)

        // --- Activity Indicator ---
        activityIndicator.color = .white
        activityIndicator.hidesWhenStopped = true
        activityIndicator.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(activityIndicator)

        // --- Layout ---
        NSLayoutConstraint.activate([
            // Image view fills safe area
            imageView.topAnchor.constraint(equalTo: compatSafeAreaTop),
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            // Overlay matches image view
            cropOverlay.topAnchor.constraint(equalTo: imageView.topAnchor),
            cropOverlay.leadingAnchor.constraint(equalTo: imageView.leadingAnchor),
            cropOverlay.trailingAnchor.constraint(equalTo: imageView.trailingAnchor),
            cropOverlay.bottomAnchor.constraint(equalTo: imageView.bottomAnchor),

            // Instruction above buttons
            instructionLabel.bottomAnchor.constraint(equalTo: backButton.topAnchor, constant: -8),
            instructionLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            instructionLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            // Bottom button row
            backButton.bottomAnchor.constraint(equalTo: compatSafeAreaBottom, constant: -12),
            backButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            backButton.widthAnchor.constraint(equalToConstant: 80),
            backButton.heightAnchor.constraint(equalToConstant: 44),

            resetButton.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            resetButton.leadingAnchor.constraint(equalTo: backButton.trailingAnchor, constant: 8),
            resetButton.widthAnchor.constraint(equalToConstant: 70),
            resetButton.heightAnchor.constraint(equalToConstant: 36),

            previewButton.centerYAnchor.constraint(equalTo: backButton.centerYAnchor),
            previewButton.trailingAnchor.constraint(equalTo: confirmButton.leadingAnchor, constant: -10),
            previewButton.widthAnchor.constraint(equalToConstant: 110),
            previewButton.heightAnchor.constraint(equalToConstant: 44),

            confirmButton.bottomAnchor.constraint(equalTo: compatSafeAreaBottom, constant: -12),
            confirmButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            confirmButton.widthAnchor.constraint(equalToConstant: 90),
            confirmButton.heightAnchor.constraint(equalToConstant: 48),

            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        // Preview inset layout
        NSLayoutConstraint.activate([
            previewInsetView.topAnchor.constraint(equalTo: compatSafeAreaTop, constant: 12),
            previewInsetView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            previewInsetView.widthAnchor.constraint(equalToConstant: 110),
            previewInsetView.heightAnchor.constraint(equalToConstant: 155)
        ])
    }

    private func setupPreviewInset() {
        previewInsetView.backgroundColor = UIColor.black.withAlphaComponent(0.75)
        previewInsetView.layer.cornerRadius = 10
        previewInsetView.layer.borderColor = UIColor.white.withAlphaComponent(0.4).cgColor
        previewInsetView.layer.borderWidth = 1
        previewInsetView.clipsToBounds = true
        previewInsetView.isHidden = true
        previewInsetView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(previewInsetView)

        previewInsetImageView.contentMode = .scaleAspectFit
        previewInsetImageView.backgroundColor = .clear
        previewInsetImageView.translatesAutoresizingMaskIntoConstraints = false
        previewInsetView.addSubview(previewInsetImageView)

        previewInsetLabel.text = "校正预览"
        previewInsetLabel.textColor = .white
        previewInsetLabel.font = UIFont.systemFont(ofSize: 11)
        previewInsetLabel.textAlignment = .center
        previewInsetLabel.translatesAutoresizingMaskIntoConstraints = false
        previewInsetView.addSubview(previewInsetLabel)

        NSLayoutConstraint.activate([
            previewInsetLabel.topAnchor.constraint(equalTo: previewInsetView.topAnchor, constant: 4),
            previewInsetLabel.leadingAnchor.constraint(equalTo: previewInsetView.leadingAnchor),
            previewInsetLabel.trailingAnchor.constraint(equalTo: previewInsetView.trailingAnchor),

            previewInsetImageView.topAnchor.constraint(equalTo: previewInsetLabel.bottomAnchor, constant: 2),
            previewInsetImageView.leadingAnchor.constraint(equalTo: previewInsetView.leadingAnchor, constant: 4),
            previewInsetImageView.trailingAnchor.constraint(equalTo: previewInsetView.trailingAnchor, constant: -4),
            previewInsetImageView.bottomAnchor.constraint(equalTo: previewInsetView.bottomAnchor, constant: -4)
        ])
    }

    // MARK: - Corner Setup
    private func setupCorners() {
        if !initialCorners.isEmpty {
            cropOverlay.setCorners(initialCorners)
        } else {
            setupDefaultCorners()
        }
    }

    /// Sets default corners at 15% inset from each edge.
    private func setupDefaultCorners() {
        let inset: CGFloat = 0.15
        let w = cropOverlay.bounds.width
        let h = cropOverlay.bounds.height
        guard w > 0, h > 0 else { return }
        cropOverlay.setCorners([
            CGPoint(x: w * inset, y: h * inset),                  // topLeft
            CGPoint(x: w * (1 - inset), y: h * inset),            // topRight
            CGPoint(x: w * (1 - inset), y: h * (1 - inset)),      // bottomRight
            CGPoint(x: w * inset, y: h * (1 - inset))             // bottomLeft
        ])
    }

    // MARK: - Actions
    @objc private func backTapped() {
        onCancel?()
    }

    @objc private func resetTapped() {
        if !initialCorners.isEmpty {
            cropOverlay.setCorners(initialCorners)
        } else {
            setupDefaultCorners()
        }
        instructionLabel.text = "拖动四个角标记文档区域"
        previewInsetView.isHidden = true
        isShowingCorrectedPreview = false
        imageView.image = sourceImage
    }

    @objc private func previewTapped() {
        let corners = cropOverlay.corners
        guard corners.count == 4 else { return }

        activityIndicator.startAnimating()

        // Convert overlay coordinates to image coordinates, then do perspective correction
        let imageCorners = convertOverlayCornersToImageSpace(corners)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            guard let corrected = self.performPerspectiveCorrection(corners: imageCorners) else {
                DispatchQueue.main.async {
                    self.activityIndicator.stopAnimating()
                    self.showAlert(title: "校正失败", message: "无法进行透视校正，请调整四角位置")
                }
                return
            }

            DispatchQueue.main.async {
                self.activityIndicator.stopAnimating()
                self.previewInsetImageView.image = corrected
                self.previewInsetView.isHidden = false
                self.instructionLabel.text = "校正预览已更新，确认无误后点击 ✓ 确认"
                self.isShowingCorrectedPreview = true
            }
        }
    }

    @objc private func confirmTapped() {
        let corners = cropOverlay.corners
        guard corners.count == 4 else {
            showAlert(title: "提示", message: "请先调整四角标记文档区域")
            return
        }

        activityIndicator.startAnimating()
        confirmButton.isEnabled = false

        let imageCorners = convertOverlayCornersToImageSpace(corners)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            guard let corrected = self.performPerspectiveCorrection(corners: imageCorners) else {
                DispatchQueue.main.async {
                    self.activityIndicator.stopAnimating()
                    self.confirmButton.isEnabled = true
                    self.showAlert(title: "校正失败", message: "无法进行透视校正，请调整四角位置")
                }
                return
            }

            DispatchQueue.main.async {
                self.activityIndicator.stopAnimating()
                self.onConfirm?(corrected)
            }
        }
    }

    // MARK: - Coordinate Conversion
    /// Converts corner coordinates from the cropOverlay (which matches imageView bounds
    /// with scaleAspectFit) to the actual source image pixel coordinate space.
    private func convertOverlayCornersToImageSpace(_ overlayCorners: [CGPoint]) -> [CGPoint] {
        let imageSize = sourceImage.size
        let displayRect = imageDisplayRect()

        guard displayRect.width > 0, displayRect.height > 0 else {
            // Fallback: simple proportional mapping
            return overlayCorners.map { pt in
                CGPoint(
                    x: (pt.x / cropOverlay.bounds.width) * imageSize.width,
                    y: (pt.y / cropOverlay.bounds.height) * imageSize.height
                )
            }
        }

        return overlayCorners.map { pt in
            // Map from overlay coordinates → display rect relative coordinates → image pixels
            let relX = (pt.x - displayRect.origin.x) / displayRect.size.width
            let relY = (pt.y - displayRect.origin.y) / displayRect.size.height

            return CGPoint(
                x: relX * imageSize.width,
                y: relY * imageSize.height
            )
        }
    }

    /// Computes the actual frame of the image within the imageView when using .scaleAspectFit.
    private func imageDisplayRect() -> CGRect {
        let imageSize = sourceImage.size
        let viewSize = imageView.bounds.size

        guard imageSize.width > 0, imageSize.height > 0,
              viewSize.width > 0, viewSize.height > 0 else { return .zero }

        let imageAspect = imageSize.width / imageSize.height
        let viewAspect = viewSize.width / viewSize.height

        var rect = CGRect.zero
        if imageAspect > viewAspect {
            // Image is wider than view → letterbox top & bottom
            rect.size.width = viewSize.width
            rect.size.height = viewSize.width / imageAspect
            rect.origin.x = 0
            rect.origin.y = (viewSize.height - rect.size.height) / 2
        } else {
            // Image is taller than view → letterbox left & right
            rect.size.height = viewSize.height
            rect.size.width = viewSize.height * imageAspect
            rect.origin.y = 0
            rect.origin.x = (viewSize.width - rect.size.width) / 2
        }
        return rect
    }

    // MARK: - Perspective Correction
    /// Applies CIPerspectiveCorrection to warp the quadrilateral into a rectangle.
    private func performPerspectiveCorrection(corners: [CGPoint]) -> UIImage? {
        guard corners.count == 4 else { return nil }

        // Fix image orientation first — CIImage doesn't respect UIImage orientation
        let fixedImage: UIImage
        if sourceImage.imageOrientation != .up {
            fixedImage = fixImageOrientation(sourceImage)
        } else {
            fixedImage = sourceImage
        }

        guard let ciImage = CIImage(image: fixedImage) else { return nil }

        let imageHeight = ciImage.extent.height

        // Core Image uses bottom-left origin; flip Y from UIKit coords (top-left origin)
        let ciCorners = corners.map { pt -> CGPoint in
            CGPoint(x: pt.x, y: imageHeight - pt.y)
        }

        // Sort into topLeft, topRight, bottomRight, bottomLeft (in CI's bottom-left space,
        // "top" means higher Y value)
        let sorted = sortCornersForCI(ciCorners)

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

    /// Sorts four corners into: topLeft, topRight, bottomRight, bottomLeft.
    /// In Core Image coordinate space (bottom-left origin), "top" = higher Y.
    private func sortCornersForCI(_ corners: [CGPoint]) -> [CGPoint] {
        // Sort by Y descending (top of image = higher Y in CI space)
        let sortedByY = corners.sorted { $0.y > $1.y }

        // Top two (higher Y) sorted by X ascending
        let topTwo = [sortedByY[0], sortedByY[1]].sorted { $0.x < $1.x }
        let topLeft = topTwo[0]
        let topRight = topTwo[1]

        // Bottom two (lower Y) sorted by X ascending
        let bottomTwo = [sortedByY[2], sortedByY[3]].sorted { $0.x < $1.x }
        let bottomLeft = bottomTwo[0]
        let bottomRight = bottomTwo[1]

        return [topLeft, topRight, bottomRight, bottomLeft]
    }

    /// Renders the UIImage with its orientation applied, so the resulting
    /// CGImage is always upright (orientation = .up).
    private func fixImageOrientation(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }

        UIGraphicsBeginImageContextWithOptions(image.size, false, image.scale)
        image.draw(in: CGRect(origin: .zero, size: image.size))
        let normalized = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return normalized ?? image
    }
}
