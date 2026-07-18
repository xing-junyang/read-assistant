import UIKit

// MARK: - Result View Controller
/// Displays the scoring result with overall score and detailed diff list.
final class ResultViewController: UIViewController {

    // MARK: - Properties
    private let result: DiffResult

    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let scoreCircleView = UIView()
    private let scoreLabel = UILabel()
    private let scoreDescriptionLabel = UILabel()
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let expectedFullTextLabel = UILabel()
    private let actualFullTextLabel = UILabel()

    // MARK: - Initialization
    init(result: DiffResult) {
        self.result = result
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    // MARK: - UI Setup
    private func setupUI() {
        view.backgroundColor = .background
        title = "阅读评分"

        // ScrollView
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        // Content Stack
        contentStack.axis = .vertical
        contentStack.spacing = 0
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentStack)

        // Score Circle Section
        let scoreSection = createScoreSection()
        contentStack.addArrangedSubview(scoreSection)

        // Separator
        let sep1 = createSeparator()
        contentStack.addArrangedSubview(sep1)

        // Diff Table Header
        let diffHeader = createSectionHeader(title: "差异详情")
        contentStack.addArrangedSubview(diffHeader)

        // TableView for diff results
        tableView.register(DiffResultCell.self, forCellReuseIdentifier: DiffResultCell.reuseIdentifier)
        tableView.delegate = self
        tableView.dataSource = self
        tableView.separatorStyle = .singleLine
        tableView.separatorColor = .separator
        tableView.backgroundColor = .clear
        tableView.isScrollEnabled = false
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 60
        contentStack.addArrangedSubview(tableView)
        tableView.heightAnchor.constraint(equalToConstant: CGFloat(result.differences.count * 60 + 20)).isActive = true

        // Separator
        let sep2 = createSeparator()
        contentStack.addArrangedSubview(sep2)

        // Full Text Comparison
        let fullTextHeader = createSectionHeader(title: "全文对比")
        contentStack.addArrangedSubview(fullTextHeader)

        // Expected text
        let expectedHeader = UILabel()
        expectedHeader.text = "期望文本："
        expectedHeader.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        expectedHeader.textColor = .textSecondary
        expectedHeader.translatesAutoresizingMaskIntoConstraints = false
        let expectedHeaderContainer = UIView()
        expectedHeaderContainer.addSubview(expectedHeader)
        NSLayoutConstraint.activate([
            expectedHeader.topAnchor.constraint(equalTo: expectedHeaderContainer.topAnchor, constant: 8),
            expectedHeader.bottomAnchor.constraint(equalTo: expectedHeaderContainer.bottomAnchor, constant: -4),
            expectedHeader.leadingAnchor.constraint(equalTo: expectedHeaderContainer.leadingAnchor, constant: 16),
            expectedHeader.trailingAnchor.constraint(equalTo: expectedHeaderContainer.trailingAnchor, constant: -16)
        ])
        contentStack.addArrangedSubview(expectedHeaderContainer)

        let expectedTextContainer = UIView()
        expectedTextContainer.backgroundColor = .cardBackground
        expectedTextContainer.layer.cornerRadius = 8
        expectedFullTextLabel.text = result.expectedText
        expectedFullTextLabel.font = UIFont.systemFont(ofSize: 14)
        expectedFullTextLabel.textColor = .textPrimary
        expectedFullTextLabel.numberOfLines = 0
        expectedFullTextLabel.translatesAutoresizingMaskIntoConstraints = false
        expectedTextContainer.addSubview(expectedFullTextLabel)
        NSLayoutConstraint.activate([
            expectedFullTextLabel.topAnchor.constraint(equalTo: expectedTextContainer.topAnchor, constant: 12),
            expectedFullTextLabel.bottomAnchor.constraint(equalTo: expectedTextContainer.bottomAnchor, constant: -12),
            expectedFullTextLabel.leadingAnchor.constraint(equalTo: expectedTextContainer.leadingAnchor, constant: 16),
            expectedFullTextLabel.trailingAnchor.constraint(equalTo: expectedTextContainer.trailingAnchor, constant: -16)
        ])
        contentStack.addArrangedSubview(expectedTextContainer)

        // Spacer
        let spacer = UIView()
        spacer.heightAnchor.constraint(equalToConstant: 8).isActive = true
        contentStack.addArrangedSubview(spacer)

        // Actual text
        let actualHeader = UILabel()
        actualHeader.text = "识别文本："
        actualHeader.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        actualHeader.textColor = .textSecondary
        actualHeader.translatesAutoresizingMaskIntoConstraints = false
        let actualHeaderContainer = UIView()
        actualHeaderContainer.addSubview(actualHeader)
        NSLayoutConstraint.activate([
            actualHeader.topAnchor.constraint(equalTo: actualHeaderContainer.topAnchor, constant: 8),
            actualHeader.bottomAnchor.constraint(equalTo: actualHeaderContainer.bottomAnchor, constant: -4),
            actualHeader.leadingAnchor.constraint(equalTo: actualHeaderContainer.leadingAnchor, constant: 16),
            actualHeader.trailingAnchor.constraint(equalTo: actualHeaderContainer.trailingAnchor, constant: -16)
        ])
        contentStack.addArrangedSubview(actualHeaderContainer)

        let actualTextContainer = UIView()
        actualTextContainer.backgroundColor = .cardBackground
        actualTextContainer.layer.cornerRadius = 8
        actualFullTextLabel.text = result.actualText
        actualFullTextLabel.font = UIFont.systemFont(ofSize: 14)
        actualFullTextLabel.textColor = .primary
        actualFullTextLabel.numberOfLines = 0
        actualFullTextLabel.translatesAutoresizingMaskIntoConstraints = false
        actualTextContainer.addSubview(actualFullTextLabel)
        NSLayoutConstraint.activate([
            actualFullTextLabel.topAnchor.constraint(equalTo: actualTextContainer.topAnchor, constant: 12),
            actualFullTextLabel.bottomAnchor.constraint(equalTo: actualTextContainer.bottomAnchor, constant: -12),
            actualFullTextLabel.leadingAnchor.constraint(equalTo: actualTextContainer.leadingAnchor, constant: 16),
            actualFullTextLabel.trailingAnchor.constraint(equalTo: actualTextContainer.trailingAnchor, constant: -16)
        ])
        contentStack.addArrangedSubview(actualTextContainer)

        // Layout
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: compatSafeAreaTop),
            scrollView.bottomAnchor.constraint(equalTo: compatSafeAreaBottom),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            contentStack.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: -24),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentStack.widthAnchor.constraint(equalTo: scrollView.widthAnchor)
        ])
    }

    private func createScoreSection() -> UIView {
        let container = UIView()
        container.backgroundColor = .cardBackground

        // Score circle background
        let circleSize: CGFloat = 120
        let circleView = UIView()
        circleView.layer.cornerRadius = circleSize / 2
        circleView.backgroundColor = scoreColor
        circleView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(circleView)

        scoreLabel.text = "\(Int(result.score))"
        scoreLabel.font = UIFont.systemFont(ofSize: 42, weight: .bold)
        scoreLabel.textColor = .white
        scoreLabel.textAlignment = .center
        scoreLabel.translatesAutoresizingMaskIntoConstraints = false
        circleView.addSubview(scoreLabel)

        let percentLabel = UILabel()
        percentLabel.text = "分"
        percentLabel.font = UIFont.systemFont(ofSize: 14)
        percentLabel.textColor = UIColor.white.withAlphaComponent(0.8)
        percentLabel.textAlignment = .center
        percentLabel.translatesAutoresizingMaskIntoConstraints = false
        circleView.addSubview(percentLabel)

        scoreDescriptionLabel.text = scoreDescription
        scoreDescriptionLabel.font = UIFont.systemFont(ofSize: 15)
        scoreDescriptionLabel.textColor = .textSecondary
        scoreDescriptionLabel.textAlignment = .center
        scoreDescriptionLabel.numberOfLines = 0
        scoreDescriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(scoreDescriptionLabel)

        // Stats
        let correctCount = result.differences.filter { $0.type == .correct }.count
        let missingCount = result.differences.filter { $0.type == .missing }.count
        let extraCount = result.differences.filter { $0.type == .extra }.count
        let wrongCount = result.differences.filter { $0.type == .wrong }.count

        let statsLabel = UILabel()
        statsLabel.text = "正确: \(correctCount) | 遗漏: \(missingCount) | 多余: \(extraCount) | 错误: \(wrongCount)"
        statsLabel.font = UIFont.systemFont(ofSize: 11)
        statsLabel.textColor = .textTertiary
        statsLabel.textAlignment = .center
        statsLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(statsLabel)

        NSLayoutConstraint.activate([
            circleView.topAnchor.constraint(equalTo: container.topAnchor, constant: 24),
            circleView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            circleView.widthAnchor.constraint(equalToConstant: circleSize),
            circleView.heightAnchor.constraint(equalToConstant: circleSize),

            scoreLabel.centerXAnchor.constraint(equalTo: circleView.centerXAnchor),
            scoreLabel.centerYAnchor.constraint(equalTo: circleView.centerYAnchor, constant: -8),

            percentLabel.topAnchor.constraint(equalTo: scoreLabel.bottomAnchor, constant: -2),
            percentLabel.centerXAnchor.constraint(equalTo: circleView.centerXAnchor),

            scoreDescriptionLabel.topAnchor.constraint(equalTo: circleView.bottomAnchor, constant: 12),
            scoreDescriptionLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            scoreDescriptionLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),

            statsLabel.topAnchor.constraint(equalTo: scoreDescriptionLabel.bottomAnchor, constant: 8),
            statsLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            statsLabel.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            statsLabel.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16)
        ])

        return container
    }

    private func createSectionHeader(title: String) -> UIView {
        let container = UIView()
        container.backgroundColor = .background

        let label = UILabel()
        label.text = title
        label.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        label.textColor = .textPrimary
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)

        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16)
        ])

        return container
    }

    private func createSeparator() -> UIView {
        let view = UIView()
        view.backgroundColor = .separator
        view.heightAnchor.constraint(equalToConstant: 8).isActive = true
        return view
    }

    // MARK: - Helpers
    private var scoreColor: UIColor {
        if result.score >= 90 { return .successGreen }
        if result.score >= 70 { return .primary }
        if result.score >= 50 { return .warningOrange }
        return .errorRed
    }

    private var scoreDescription: String {
        if result.score >= 95 { return "非常出色！朗读几乎完美匹配期望文本。" }
        if result.score >= 85 { return "表现优秀！只有少量差异。" }
        if result.score >= 70 { return "表现良好，还有一些可以改进的地方。" }
        if result.score >= 50 { return "需要多加练习，有不少差异。" }
        return "还需要大量练习，差异较多。"
    }
}

// MARK: - UITableViewDataSource
extension ResultViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return result.differences.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: DiffResultCell.reuseIdentifier, for: indexPath) as? DiffResultCell else {
            return UITableViewCell()
        }
        cell.configure(with: result.differences[indexPath.row])
        return cell
    }
}

// MARK: - UITableViewDelegate
extension ResultViewController: UITableViewDelegate {}
