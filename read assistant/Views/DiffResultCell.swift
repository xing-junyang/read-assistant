import UIKit

// MARK: - Diff Result Cell
/// Custom UITableViewCell for displaying a single diff segment result.
final class DiffResultCell: UITableViewCell {

    // MARK: - Identifier
    static let reuseIdentifier = "DiffResultCell"

    // MARK: - Subviews
    private let typeIndicator = UIView()
    private let typeLabel = UILabel()
    private let expectedLabel = UILabel()
    private let actualLabel = UILabel()
    private let arrowLabel = UILabel()

    // MARK: - Initialization
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - UI Setup
    private func setupUI() {
        backgroundColor = .cardBackground
        selectionStyle = .none

        // Type indicator (colored dot)
        typeIndicator.layer.cornerRadius = 6
        typeIndicator.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(typeIndicator)

        // Type label (正确/缺失/多余/错误)
        typeLabel.font = UIFont.systemFont(ofSize: 12, weight: .medium)
        typeLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(typeLabel)

        // Expected text
        expectedLabel.font = UIFont.systemFont(ofSize: 14)
        expectedLabel.numberOfLines = 0
        expectedLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(expectedLabel)

        // Arrow
        arrowLabel.font = UIFont.systemFont(ofSize: 14)
        arrowLabel.textAlignment = .center
        arrowLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(arrowLabel)

        // Actual text
        actualLabel.font = UIFont.systemFont(ofSize: 14)
        actualLabel.numberOfLines = 0
        actualLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(actualLabel)

        NSLayoutConstraint.activate([
            typeIndicator.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            typeIndicator.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            typeIndicator.widthAnchor.constraint(equalToConstant: 12),
            typeIndicator.heightAnchor.constraint(equalToConstant: 12),

            typeLabel.centerYAnchor.constraint(equalTo: typeIndicator.centerYAnchor),
            typeLabel.leadingAnchor.constraint(equalTo: typeIndicator.trailingAnchor, constant: 6),

            expectedLabel.topAnchor.constraint(equalTo: typeIndicator.bottomAnchor, constant: 6),
            expectedLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            expectedLabel.trailingAnchor.constraint(equalTo: arrowLabel.leadingAnchor, constant: -4),

            arrowLabel.centerYAnchor.constraint(equalTo: expectedLabel.centerYAnchor),
            arrowLabel.widthAnchor.constraint(equalToConstant: 24),
            arrowLabel.trailingAnchor.constraint(equalTo: actualLabel.leadingAnchor, constant: -4),

            actualLabel.topAnchor.constraint(equalTo: expectedLabel.topAnchor),
            actualLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            contentView.bottomAnchor.constraint(equalTo: expectedLabel.bottomAnchor, constant: 10),
            contentView.bottomAnchor.constraint(greaterThanOrEqualTo: actualLabel.bottomAnchor, constant: 10)
        ])
    }

    // MARK: - Configuration
    func configure(with segment: DiffSegment) {
        switch segment.type {
        case .correct:
            typeIndicator.backgroundColor = .successGreen
            typeLabel.text = "正确"
            typeLabel.textColor = .successGreen
            expectedLabel.text = segment.expectedSegment
            expectedLabel.textColor = .textPrimary
            actualLabel.text = segment.actualSegment
            actualLabel.textColor = .textPrimary
            arrowLabel.text = "→"
            arrowLabel.textColor = .successGreen
        case .missing:
            typeIndicator.backgroundColor = .errorRed
            typeLabel.text = "遗漏"
            typeLabel.textColor = .errorRed
            expectedLabel.text = segment.expectedSegment
            expectedLabel.textColor = .errorRed
            actualLabel.text = "—"
            actualLabel.textColor = .textTertiary
            arrowLabel.text = "→"
            arrowLabel.textColor = .textTertiary
        case .extra:
            typeIndicator.backgroundColor = .warningOrange
            typeLabel.text = "多余"
            typeLabel.textColor = .warningOrange
            expectedLabel.text = "—"
            expectedLabel.textColor = .textTertiary
            actualLabel.text = segment.actualSegment
            actualLabel.textColor = .warningOrange
            arrowLabel.text = "→"
            arrowLabel.textColor = .textTertiary
        case .wrong:
            typeIndicator.backgroundColor = .errorRed
            typeLabel.text = "错误"
            typeLabel.textColor = .errorRed
            expectedLabel.text = segment.expectedSegment
            expectedLabel.textColor = .textPrimary
            actualLabel.text = segment.actualSegment
            actualLabel.textColor = .errorRed
            arrowLabel.text = "→"
            arrowLabel.textColor = .errorRed
            // Show pinyin for short errors to aid learning
            if let pinyin = segment.expectedPinyin {
                expectedLabel.text = "\(segment.expectedSegment ?? "")\n[\(pinyin)]"
            }
        case .homophone:
            typeIndicator.backgroundColor = .warningOrange
            typeLabel.text = "同音"
            typeLabel.textColor = .warningOrange
            expectedLabel.text = segment.expectedSegment
            expectedLabel.textColor = .textPrimary
            actualLabel.text = segment.actualSegment
            actualLabel.textColor = .warningOrange
            arrowLabel.text = "→"
            arrowLabel.textColor = .warningOrange
            // Show pinyin for short homophone errors
            if let pinyin = segment.expectedPinyin {
                expectedLabel.text = "\(segment.expectedSegment ?? "")\n[\(pinyin)]"
            }
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        expectedLabel.text = nil
        actualLabel.text = nil
        arrowLabel.text = nil
    }
}
