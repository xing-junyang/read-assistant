import UIKit

// MARK: - Reading Progress View
/// A custom progress view showing which expected texts have been read.
final class ReadingProgressView: UIView {

    // MARK: - Properties
    private let stackView = UIStackView()
    private var indicatorViews: [UIView] = []

    // MARK: - Initialization
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - UI Setup
    private func setupUI() {
        backgroundColor = .clear

        stackView.axis = .horizontal
        stackView.distribution = .fillEqually
        stackView.spacing = 6
        stackView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: topAnchor),
            stackView.bottomAnchor.constraint(equalTo: bottomAnchor),
            stackView.leadingAnchor.constraint(equalTo: leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
    }

    // MARK: - Configuration
    /// Configures the progress view with total count and completed indices.
    func configure(total: Int, completedIndices: Set<Int>, currentIndex: Int = -1) {
        // Clear existing
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        indicatorViews.removeAll()

        guard total > 0 else { return }

        for i in 0..<total {
            let dot = UIView()
            dot.layer.cornerRadius = 5
            dot.translatesAutoresizingMaskIntoConstraints = false
            dot.widthAnchor.constraint(equalToConstant: 10).isActive = true
            dot.heightAnchor.constraint(equalToConstant: 10).isActive = true

            if i == currentIndex {
                dot.backgroundColor = .primary
                dot.layer.borderWidth = 0
            } else if completedIndices.contains(i) {
                dot.backgroundColor = .successGreen
                dot.layer.borderWidth = 0
            } else {
                dot.backgroundColor = .clear
                dot.layer.borderWidth = 1.5
                dot.layer.borderColor = UIColor.textTertiary.cgColor
            }

            stackView.addArrangedSubview(dot)
            indicatorViews.append(dot)
        }
    }
}
