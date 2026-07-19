import UIKit

// MARK: - Task Cell
/// Custom UITableViewCell for displaying a ReadingTask in the task list.
final class TaskCell: UITableViewCell {

    // MARK: - Identifier
    static let reuseIdentifier = "TaskCell"

    // MARK: - Subviews
    private let containerView = UIView()
    private let titleLabel = UILabel()
    private let descriptionLabel = UILabel()
    private let progressLabel = UILabel()
    private let dateLabel = UILabel()
    private let statusImageView = UIImageView()

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
        backgroundColor = .clear
        selectionStyle = .none

        // Container
        containerView.backgroundColor = .cardBackground
        containerView.layer.cornerRadius = 12
        containerView.layer.shadowColor = UIColor.black.cgColor
        containerView.layer.shadowOffset = CGSize(width: 0, height: 1)
        containerView.layer.shadowRadius = 3
        containerView.layer.shadowOpacity = 0.08
        containerView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(containerView)

        // Status icon
        statusImageView.contentMode = .scaleAspectFit
        statusImageView.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(statusImageView)

        // Title
        titleLabel.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = .textPrimary
        titleLabel.numberOfLines = 2
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(titleLabel)

        // Description
        descriptionLabel.font = UIFont.systemFont(ofSize: 14)
        descriptionLabel.textColor = .textSecondary
        descriptionLabel.numberOfLines = 1
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(descriptionLabel)

        // Progress
        progressLabel.font = UIFont.systemFont(ofSize: 12)
        progressLabel.textColor = .primary
        progressLabel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(progressLabel)

        // Date
        dateLabel.font = UIFont.systemFont(ofSize: 11)
        dateLabel.textColor = .textTertiary
        dateLabel.translatesAutoresizingMaskIntoConstraints = false
        containerView.addSubview(dateLabel)

        // Layout
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            containerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
            containerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            containerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            statusImageView.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 14),
            statusImageView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -14),
            statusImageView.widthAnchor.constraint(equalToConstant: 24),
            statusImageView.heightAnchor.constraint(equalToConstant: 24),

            titleLabel.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: statusImageView.leadingAnchor, constant: -8),

            descriptionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            descriptionLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            descriptionLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),

            progressLabel.topAnchor.constraint(equalTo: descriptionLabel.bottomAnchor, constant: 6),
            progressLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),

            dateLabel.centerYAnchor.constraint(equalTo: progressLabel.centerYAnchor),
            dateLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),

            dateLabel.topAnchor.constraint(equalTo: progressLabel.bottomAnchor, constant: 6),
            containerView.bottomAnchor.constraint(greaterThanOrEqualTo: dateLabel.bottomAnchor, constant: 12)
        ])
    }

    // MARK: - Configuration
    func configure(with task: ReadingTask) {
        if task.isBuiltIn {
            titleLabel.text = "📌 \(task.title)"
        } else {
            titleLabel.text = task.title
        }
        descriptionLabel.text = task.detailDescription.isEmpty ? "暂无描述" : task.detailDescription

        let total = task.expectedTexts.count
        if total > 0 {
            let readCount = task.sessions.map { $0.expectedTextIndex }.reduce(into: Set<Int>()) { $0.insert($1) }.count
            progressLabel.text = "进度：\(readCount)/\(total)"
        } else {
            progressLabel.text = "暂无阅读文本"
        }

        dateLabel.text = task.modifiedAt.shortChineseFormat

        if task.isCompleted {
            statusImageView.image = UIImage(named: "checkmark.circle.fill") ?? drawCheckmarkIcon(filled: true)
            statusImageView.tintColor = .successGreen
        } else {
            statusImageView.image = UIImage(named: "circle") ?? drawCheckmarkIcon(filled: false)
            statusImageView.tintColor = .textTertiary
        }
    }

    /// Draws a simple checkmark circle icon programmatically (iOS 10 compatible, no SF Symbols).
    private func drawCheckmarkIcon(filled: Bool) -> UIImage? {
        let size = CGSize(width: 24, height: 24)
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        guard let ctx = UIGraphicsGetCurrentContext() else { return nil }

        let rect = CGRect(x: 2, y: 2, width: 20, height: 20)

        if filled {
            ctx.setFillColor(UIColor.successGreen.cgColor)
            ctx.fillEllipse(in: rect)
            // Draw checkmark
            ctx.setStrokeColor(UIColor.white.cgColor)
            ctx.setLineWidth(2)
            ctx.move(to: CGPoint(x: 8, y: 12))
            ctx.addLine(to: CGPoint(x: 11, y: 15))
            ctx.addLine(to: CGPoint(x: 16, y: 9))
            ctx.strokePath()
        } else {
            ctx.setStrokeColor(UIColor.textTertiary.cgColor)
            ctx.setLineWidth(1.5)
            ctx.strokeEllipse(in: rect)
        }

        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        titleLabel.text = nil
        descriptionLabel.text = nil
        progressLabel.text = nil
        dateLabel.text = nil
        statusImageView.image = nil
    }
}
