import UIKit

// MARK: - Crop Overlay View Delegate
protocol CropOverlayViewDelegate: AnyObject {
    func cropOverlayView(_ view: CropOverlayView, didChangeCorners corners: [CGPoint])
}

// MARK: - Crop Overlay View
/// A transparent overlay that draws a quadrilateral connecting four draggable
/// corner markers. Used for selecting a document region for perspective correction.
final class CropOverlayView: UIView {

    // MARK: - Properties
    weak var delegate: CropOverlayViewDelegate?

    /// The four corners in order: topLeft(0), topRight(1), bottomRight(2), bottomLeft(3)
    private(set) var corners: [CGPoint] = [] {
        didSet { setNeedsDisplay() }
    }

    /// Size of each draggable marker circle
    private let markerSize: CGFloat = 30
    private var markers: [UIView] = []

    // MARK: - Colors
    var lineColor: UIColor = .accent {
        didSet { setNeedsDisplay() }
    }
    var fillColor: UIColor = UIColor.accent.withAlphaComponent(0.12) {
        didSet { setNeedsDisplay() }
    }
    var dimmedMaskColor: UIColor = UIColor.black.withAlphaComponent(0.35) {
        didSet { setNeedsDisplay() }
    }
    var markerColor: UIColor = .accent {
        didSet { markers.forEach { $0.backgroundColor = markerColor } }
    }

    // MARK: - Init
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .clear
        isUserInteractionEnabled = true
    }

    // MARK: - Public API
    /// Sets the four corners and updates markers. Silently ignores if count != 4.
    func setCorners(_ newCorners: [CGPoint]) {
        guard newCorners.count == 4 else { return }
        corners = newCorners
        updateMarkers()
    }

    // MARK: - Marker Management
    private func updateMarkers() {
        markers.forEach { $0.removeFromSuperview() }
        markers.removeAll()

        for (index, corner) in corners.enumerated() {
            let marker = buildMarker(at: corner, index: index)
            addSubview(marker)
            markers.append(marker)
        }
    }

    private func buildMarker(at point: CGPoint, index: Int) -> UIView {
        let marker = UIView(frame: CGRect(
            x: point.x - markerSize / 2,
            y: point.y - markerSize / 2,
            width: markerSize,
            height: markerSize
        ))
        marker.backgroundColor = markerColor
        marker.layer.cornerRadius = markerSize / 2
        marker.layer.borderColor = UIColor.white.cgColor
        marker.layer.borderWidth = 3
        marker.layer.shadowColor = UIColor.black.cgColor
        marker.layer.shadowOffset = CGSize(width: 0, height: 2)
        marker.layer.shadowRadius = 4
        marker.layer.shadowOpacity = 0.35
        marker.tag = index
        marker.isUserInteractionEnabled = true

        // Index label inside marker
        let label = UILabel(frame: marker.bounds)
        label.text = "\(index + 1)"
        label.textColor = .white
        label.font = UIFont.systemFont(ofSize: 12, weight: .bold)
        label.textAlignment = .center
        marker.addSubview(label)

        // Pan gesture for dragging
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleMarkerPan(_:)))
        marker.addGestureRecognizer(pan)

        return marker
    }

    // MARK: - Drag Handling
    @objc private func handleMarkerPan(_ gesture: UIPanGestureRecognizer) {
        guard let marker = gesture.view else { return }
        let index = marker.tag

        switch gesture.state {
        case .began:
            bringSubviewToFront(marker)
            UIView.animate(withDuration: 0.15) {
                marker.transform = CGAffineTransform(scaleX: 1.35, y: 1.35)
            }

        case .changed:
            let translation = gesture.translation(in: self)
            var newCenter = CGPoint(
                x: marker.center.x + translation.x,
                y: marker.center.y + translation.y
            )

            // Clamp inside bounds (with some padding)
            let pad = markerSize / 2
            newCenter.x = max(pad, min(bounds.width - pad, newCenter.x))
            newCenter.y = max(pad, min(bounds.height - pad, newCenter.y))

            marker.center = newCenter
            gesture.setTranslation(.zero, in: self)

            corners[index] = newCenter
            delegate?.cropOverlayView(self, didChangeCorners: corners)

        case .ended, .cancelled:
            UIView.animate(withDuration: 0.15) {
                marker.transform = .identity
            }

        default:
            break
        }
    }

    // MARK: - Drawing
    override func draw(_ rect: CGRect) {
        guard corners.count == 4, let ctx = UIGraphicsGetCurrentContext() else { return }

        // --- 1. Dimmed mask outside the quadrilateral ---
        // Fill entire rect with dim color, then clear the interior quadrilateral
        ctx.setFillColor(dimmedMaskColor.cgColor)
        ctx.fill(rect)

        // Punch a hole for the selected region
        let quadPath = buildQuadPath()
        ctx.setBlendMode(.clear)
        ctx.setFillColor(UIColor.clear.cgColor)
        ctx.addPath(quadPath.cgPath)
        ctx.fillPath()

        // Reset blend mode
        ctx.setBlendMode(.normal)

        // --- 2. Fill interior with subtle highlight ---
        ctx.setFillColor(fillColor.cgColor)
        ctx.addPath(quadPath.cgPath)
        ctx.fillPath()

        // --- 3. Stroke the border ---
        ctx.setStrokeColor(lineColor.cgColor)
        ctx.setLineWidth(3.0)
        ctx.setLineDash(phase: 0, lengths: [])
        ctx.addPath(quadPath.cgPath)
        ctx.strokePath()

        // --- 4. Small white dots at each corner (behind markers) ---
        ctx.setFillColor(UIColor.white.cgColor)
        for corner in corners {
            let dotRect = CGRect(x: corner.x - 5, y: corner.y - 5, width: 10, height: 10)
            ctx.fillEllipse(in: dotRect)
        }
    }

    private func buildQuadPath() -> UIBezierPath {
        let path = UIBezierPath()
        path.move(to: corners[0])
        path.addLine(to: corners[1])
        path.addLine(to: corners[2])
        path.addLine(to: corners[3])
        path.close()
        return path
    }
}
