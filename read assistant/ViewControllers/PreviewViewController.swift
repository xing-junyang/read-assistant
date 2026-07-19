import UIKit

// MARK: - Preview View Controller
/// A lightweight view controller used for 3D Touch peek previews.
/// Displays full expected text or historical session details.
/// Compatible with iOS 10+.
final class PreviewViewController: UIViewController {

    // MARK: - Preview Content Type
    enum PreviewContent {
        /// Previewing an expected reading text.
        case expectedText(text: String, index: Int, total: Int)
        /// Previewing a historical reading session result.
        case sessionResult(session: ReadingSession, expectedText: String?)
    }

    // MARK: - Properties
    private let content: PreviewContent
    private let scrollView = UIScrollView()
    private let contentLabel = UILabel()

    // Callback for commit (pop) action — called when user presses deeper.
    var onCommit: (() -> Void)?

    // MARK: - Initialization
    init(content: PreviewContent) {
        self.content = content
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        configureContent()
    }

    // MARK: - UI Setup
    private func setupUI() {
        view.backgroundColor = .background

        // Scroll view for long text content
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)

        // Content label
        contentLabel.font = UIFont.systemFont(ofSize: 15)
        contentLabel.textColor = .textPrimary
        contentLabel.numberOfLines = 0
        contentLabel.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentLabel)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            contentLabel.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentLabel.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentLabel.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentLabel.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentLabel.widthAnchor.constraint(equalTo: scrollView.widthAnchor)
        ])
    }

    private func configureContent() {
        switch content {
        case .expectedText(let text, let index, let total):
            configureExpectedTextPreview(text: text, index: index, total: total)

        case .sessionResult(let session, let expectedText):
            configureSessionPreview(session: session, expectedText: expectedText)
        }
    }

    // MARK: - Expected Text Preview
    private func configureExpectedTextPreview(text: String, index: Int, total: Int) {
        let attributed = NSMutableAttributedString()

        // Header
        let headerText = "📖 第 \(index + 1) 段（共 \(total) 段）\n\n"
        let headerAttr: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: UIColor.textSecondary
        ]
        attributed.append(NSAttributedString(string: headerText, attributes: headerAttr))

        // Body text
        let bodyAttr: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 16),
            .foregroundColor: UIColor.textPrimary
        ]
        attributed.append(NSAttributedString(string: text, attributes: bodyAttr))

        contentLabel.attributedText = attributed
    }

    // MARK: - Session Preview
    private func configureSessionPreview(session: ReadingSession, expectedText: String?) {
        let attributed = NSMutableAttributedString()

        // Score header
        if let result = session.result {
            let scoreText: String
            let scoreColor: UIColor
            if result.score >= 90 {
                scoreText = "🏆 得分: \(Int(result.score))% — 优秀！"
                scoreColor = .successGreen
            } else if result.score >= 70 {
                scoreText = "👍 得分: \(Int(result.score))% — 良好"
                scoreColor = .primary
            } else if result.score >= 50 {
                scoreText = "📝 得分: \(Int(result.score))% — 需改进"
                scoreColor = .warningOrange
            } else {
                scoreText = "💪 得分: \(Int(result.score))% — 继续加油"
                scoreColor = .errorRed
            }
            let scoreAttr: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 18, weight: .bold),
                .foregroundColor: scoreColor
            ]
            attributed.append(NSAttributedString(string: scoreText, attributes: scoreAttr))
            attributed.append(NSAttributedString(string: "\n\n"))
        }

        // Session time
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "zh_CN")
        dateFormatter.dateFormat = "yyyy年M月d日 HH:mm"
        let timeText = "🕐 阅读时间: \(dateFormatter.string(from: session.startTime))"
        let timeAttr: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12),
            .foregroundColor: UIColor.textSecondary
        ]
        attributed.append(NSAttributedString(string: timeText, attributes: timeAttr))
        attributed.append(NSAttributedString(string: "\n\n"))

        // Duration
        let duration = session.duration
        let durText: String
        if duration < 60 {
            durText = "⏱ 用时: \(Int(duration)) 秒"
        } else {
            durText = "⏱ 用时: \(Int(duration / 60)) 分 \(Int(duration.truncatingRemainder(dividingBy: 60))) 秒"
        }
        attributed.append(NSAttributedString(string: durText, attributes: timeAttr))
        attributed.append(NSAttributedString(string: "\n\n"))

        // Expected text (if available)
        if let expected = expectedText, !expected.isEmpty {
            let expectedHeaderAttr: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: UIColor.textSecondary
            ]
            attributed.append(NSAttributedString(string: "📖 期望文本:\n", attributes: expectedHeaderAttr))

            let expectedBodyAttr: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 14),
                .foregroundColor: UIColor.textPrimary
            ]
            attributed.append(NSAttributedString(string: expected, attributes: expectedBodyAttr))
            attributed.append(NSAttributedString(string: "\n\n"))
        }

        // Recognized text
        if !session.recognizedText.isEmpty {
            let recogHeaderAttr: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: UIColor.textSecondary
            ]
            attributed.append(NSAttributedString(string: "🎙 识别文本:\n", attributes: recogHeaderAttr))

            let recogBodyAttr: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 14),
                .foregroundColor: UIColor.primary
            ]
            attributed.append(NSAttributedString(string: session.recognizedText, attributes: recogBodyAttr))
        } else {
            let noTextAttr: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 14),
                .foregroundColor: UIColor.textTertiary
            ]
            attributed.append(NSAttributedString(string: "（无识别文本）", attributes: noTextAttr))
        }

        contentLabel.attributedText = attributed
    }

    // MARK: - Preview Action Items (iOS 10+)
    /// Returns preview actions shown when swiping up on the peek.
    override var previewActionItems: [UIPreviewActionItem] {
        switch content {
        case .expectedText:
            let copyAction = UIPreviewAction(title: "复制文本", style: .default) { [weak self] _, _ in
                guard case .expectedText(let text, _, _)? = self?.content else { return }
                UIPasteboard.general.string = text
            }
            return [copyAction]

        case .sessionResult(let session, _):
            var actions: [UIPreviewAction] = []

            if let result = session.result {
                let viewAction = UIPreviewAction(title: "查看详细评分", style: .default) { [weak self] _, _ in
                    self?.onCommit?()
                }
                actions.append(viewAction)
            }

            if !session.recognizedText.isEmpty {
                let copyAction = UIPreviewAction(title: "复制识别文本", style: .default) { _, _ in
                    UIPasteboard.general.string = session.recognizedText
                }
                actions.append(copyAction)
            }

            return actions
        }
    }
}
