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

        // Arrow — always centered between expected and actual
        arrowLabel.font = UIFont.systemFont(ofSize: 14)
        arrowLabel.textAlignment = .center
        arrowLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(arrowLabel)

        // Expected text (left side, truncated to 20 chars)
        expectedLabel.font = UIFont.systemFont(ofSize: 14)
        expectedLabel.numberOfLines = 1
        expectedLabel.lineBreakMode = .byTruncatingTail
        expectedLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(expectedLabel)

        // Actual text (right side, truncated to 20 chars)
        actualLabel.font = UIFont.systemFont(ofSize: 14)
        actualLabel.numberOfLines = 1
        actualLabel.lineBreakMode = .byTruncatingTail
        actualLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(actualLabel)

        NSLayoutConstraint.activate([
            // Type indicator row (top)
            typeIndicator.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            typeIndicator.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            typeIndicator.widthAnchor.constraint(equalToConstant: 12),
            typeIndicator.heightAnchor.constraint(equalToConstant: 12),

            typeLabel.centerYAnchor.constraint(equalTo: typeIndicator.centerYAnchor),
            typeLabel.leadingAnchor.constraint(equalTo: typeIndicator.trailingAnchor, constant: 6),

            // Arrow — centered horizontally, below the type row
            arrowLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            arrowLabel.topAnchor.constraint(equalTo: typeIndicator.bottomAnchor, constant: 8),
            arrowLabel.widthAnchor.constraint(equalToConstant: 24),

            // Expected text (left of arrow)
            expectedLabel.centerYAnchor.constraint(equalTo: arrowLabel.centerYAnchor),
            expectedLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            expectedLabel.trailingAnchor.constraint(equalTo: arrowLabel.leadingAnchor, constant: -4),

            // Actual text (right of arrow)
            actualLabel.centerYAnchor.constraint(equalTo: arrowLabel.centerYAnchor),
            actualLabel.leadingAnchor.constraint(equalTo: arrowLabel.trailingAnchor, constant: 4),
            actualLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            // Bottom anchor
            contentView.bottomAnchor.constraint(equalTo: arrowLabel.bottomAnchor, constant: 10)
        ])
    }

    // MARK: - Helpers

    /// Truncates text to `maxLength` characters, appending "…" if needed.
    private func truncate(_ text: String, maxLength: Int = 20) -> String {
        if text.count <= maxLength { return text }
        return String(text.prefix(maxLength)) + "…"
    }

    // MARK: - Configuration
    func configure(with segment: DiffSegment) {
        switch segment.type {
        case .correct:
            typeIndicator.backgroundColor = .successGreen
            typeLabel.text = "正确"
            typeLabel.textColor = .successGreen
            expectedLabel.text = truncate(segment.expectedSegment ?? "")
            expectedLabel.textColor = .textPrimary
            actualLabel.text = truncate(segment.actualSegment ?? "")
            actualLabel.textColor = .textPrimary
            arrowLabel.text = "→"
            arrowLabel.textColor = .successGreen
        case .missing:
            typeIndicator.backgroundColor = .errorRed
            typeLabel.text = "遗漏"
            typeLabel.textColor = .errorRed
            expectedLabel.text = truncate(segment.expectedSegment ?? "")
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
            actualLabel.text = truncate(segment.actualSegment ?? "")
            actualLabel.textColor = .warningOrange
            arrowLabel.text = "→"
            arrowLabel.textColor = .textTertiary
        case .wrong:
            typeIndicator.backgroundColor = .errorRed
            typeLabel.text = "错误"
            typeLabel.textColor = .errorRed
            expectedLabel.text = truncate(segment.expectedSegment ?? "")
            expectedLabel.textColor = .textPrimary
            actualLabel.text = truncate(segment.actualSegment ?? "")
            actualLabel.textColor = .errorRed
            arrowLabel.text = "→"
            arrowLabel.textColor = .errorRed
            // Show pinyin for short errors to aid learning
            if let pinyin = segment.expectedPinyin {
                expectedLabel.text = "\(truncate(segment.expectedSegment ?? ""))\n[\(pinyin)]"
                expectedLabel.numberOfLines = 2
            } else {
                expectedLabel.numberOfLines = 1
            }
        case .homophone:
            typeIndicator.backgroundColor = .warningOrange
            typeLabel.text = "同音"
            typeLabel.textColor = .warningOrange
            expectedLabel.text = truncate(segment.expectedSegment ?? "")
            expectedLabel.textColor = .textPrimary
            actualLabel.text = truncate(segment.actualSegment ?? "")
            actualLabel.textColor = .warningOrange
            arrowLabel.text = "→"
            arrowLabel.textColor = .warningOrange
            // Show pinyin for short homophone errors
            if let pinyin = segment.expectedPinyin {
                expectedLabel.text = "\(truncate(segment.expectedSegment ?? ""))\n[\(pinyin)]"
                expectedLabel.numberOfLines = 2
            } else {
                expectedLabel.numberOfLines = 1
            }
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        expectedLabel.text = nil
        expectedLabel.numberOfLines = 1
        actualLabel.text = nil
        arrowLabel.text = nil
    }
}
