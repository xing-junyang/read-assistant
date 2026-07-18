import UIKit

// MARK: - Task Detail View Controller
/// Shows task details, expected texts, and allows starting a reading session.
final class TaskDetailViewController: UIViewController {

    // MARK: - Properties
    private let taskId: String
    private var task: ReadingTask? {
        return TaskManager.shared.task(withId: taskId)
    }

    private let tableView = UITableView(frame: .zero, style: .grouped)
    private let startReadingButton = UIButton(type: .system)

    // MARK: - Initialization
    init(taskId: String) {
        self.taskId = taskId
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupTableView()
        setupStartButton()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.reloadData()
        updateStartButton()
    }

    // MARK: - UI Setup
    private func setupUI() {
        view.backgroundColor = .background
        title = task?.title ?? "任务详情"

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .add,
            target: self,
            action: #selector(addExpectedText)
        )
    }

    private func setupTableView() {
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "ExpectedTextCell")
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "OverviewCell")
        tableView.backgroundColor = .background
        tableView.separatorColor = .separator
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 60
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
    }

    private func setupStartButton() {
        startReadingButton.setTitle("开始阅读", for: .normal)
        startReadingButton.titleLabel?.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        startReadingButton.setTitleColor(.white, for: .normal)
        startReadingButton.backgroundColor = .primary
        startReadingButton.layer.cornerRadius = 12
        startReadingButton.addTarget(self, action: #selector(startReadingTapped), for: .touchUpInside)
        startReadingButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(startReadingButton)

        NSLayoutConstraint.activate([
            startReadingButton.topAnchor.constraint(equalTo: tableView.bottomAnchor, constant: 12),
            startReadingButton.bottomAnchor.constraint(equalTo: compatSafeAreaBottom, constant: -16),
            startReadingButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            startReadingButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            startReadingButton.heightAnchor.constraint(equalToConstant: 50)
        ])
    }

    private func updateStartButton() {
        guard let task = task else { return }
        let hasTexts = !task.expectedTexts.isEmpty
        startReadingButton.isEnabled = hasTexts
        startReadingButton.alpha = hasTexts ? 1.0 : 0.5
        if hasTexts {
            startReadingButton.setTitle("开始阅读", for: .normal)
            startReadingButton.backgroundColor = .primary
        } else {
            startReadingButton.setTitle("暂无文本", for: .normal)
            startReadingButton.backgroundColor = .textSecondary
        }
    }

    // MARK: - Actions

    @objc private func addExpectedText() {
        showActionSheet(title: "添加阅读文本", actions: [
            ("手动输入", .default, { [weak self] in self?.showManualInput() }),
            ("OCR 拍照识别", .default, { [weak self] in self?.showOCRScanner() })
        ])
    }

    private func showManualInput() {
        // Present a multi-line text input
        let inputVC = TextInputViewController()
        inputVC.onSave = { [weak self] text in
            guard let self = self, let task = self.task else { return }
            // Auto-parse newlines into separate expected text paragraphs
            let paragraphs = text.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            for paragraph in paragraphs {
                task.expectedTexts.append(paragraph)
            }
            TaskManager.shared.updateTask(task)
            self.tableView.reloadData()
            self.updateStartButton()
        }
        let nav = UINavigationController(rootViewController: inputVC)
        present(nav, animated: true)
    }

    private func showOCRScanner() {
        let ocrVC = OCRScanViewController()
        ocrVC.onTextRecognized = { [weak self] text in
            guard let self = self, let task = self.task else { return }
            // Auto-parse newlines into separate expected text paragraphs
            let paragraphs = text.components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            for paragraph in paragraphs {
                task.expectedTexts.append(paragraph)
            }
            TaskManager.shared.updateTask(task)
            self.tableView.reloadData()
            self.updateStartButton()
        }
        let nav = UINavigationController(rootViewController: ocrVC)
        present(nav, animated: true)
    }

    @objc private func startReadingTapped() {
        guard let task = task, !task.expectedTexts.isEmpty else { return }
        let readingVC = ReadingViewController(taskId: task.id)
        navigationController?.pushViewController(readingVC, animated: true)
    }
}

// MARK: - UITableViewDataSource
extension TaskDetailViewController: UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        return 3
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let task = task else { return 0 }
        switch section {
        case 0: return 1 // Overview
        case 1: return task.expectedTexts.isEmpty ? 1 : task.expectedTexts.count
        case 2: return task.sessions.count
        default: return 0
        }
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch section {
        case 0: return "概览"
        case 1: return "期望阅读文本"
        case 2: return "历史阅读记录"
        default: return nil
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let task = task else { return UITableViewCell() }

        switch indexPath.section {
        case 0:
            // Overview cell with circular indicators
            let cell = tableView.dequeueReusableCell(withIdentifier: "OverviewCell", for: indexPath)
            cell.selectionStyle = .none
            cell.accessoryType = .none

            // Remove previous overview subviews (tagged 1000-1999)
            cell.contentView.subviews.filter { (1000...1999).contains($0.tag) }.forEach { $0.removeFromSuperview() }

            let totalParagraphs = task.expectedTexts.count
            let readIndices = Set(task.sessions.map { $0.expectedTextIndex })
            let readCount = task.expectedTexts.indices.filter { readIndices.contains($0) }.count
            let completionRate = totalParagraphs > 0 ? Double(readCount) / Double(totalParagraphs) : 0.0
            let totalScore = computeTotalScore(for: task)
            let hasData = totalParagraphs > 0 && readCount > 0

            // Container stack for the two circles
            let containerStack = UIStackView()
            containerStack.axis = .horizontal
            containerStack.alignment = .center
            containerStack.distribution = .fill
            containerStack.spacing = 24
            containerStack.tag = 1000
            containerStack.translatesAutoresizingMaskIntoConstraints = false
            cell.contentView.addSubview(containerStack)

            // --- Left: Completion Rate Ring ---
            let ringSize: CGFloat = 90
            let ringWidth: CGFloat = 8

            let completionContainer = UIView()
            completionContainer.tag = 1001
            completionContainer.translatesAutoresizingMaskIntoConstraints = false

            // --- Ring view: exactly ringSize × ringSize, so label centers perfectly ---
            let ringView = UIView()
            ringView.backgroundColor = .clear
            ringView.tag = 1005
            ringView.translatesAutoresizingMaskIntoConstraints = false
            completionContainer.addSubview(ringView)

            // Track ring (gray background)
            let trackLayer = CAShapeLayer()
            let center = CGPoint(x: ringSize / 2, y: ringSize / 2)
            let radius = (ringSize - ringWidth) / 2
            let ringPath = UIBezierPath(
                arcCenter: center,
                radius: radius,
                startAngle: -CGFloat.pi / 2,
                endAngle: CGFloat.pi * 1.5,
                clockwise: true
            )
            trackLayer.path = ringPath.cgPath
            trackLayer.fillColor = UIColor.clear.cgColor
            trackLayer.strokeColor = UIColor.separator.cgColor
            trackLayer.lineWidth = ringWidth
            trackLayer.lineCap = .round
            ringView.layer.addSublayer(trackLayer)

            // Progress ring (colored)
            let progressLayer = CAShapeLayer()
            progressLayer.path = ringPath.cgPath
            progressLayer.fillColor = UIColor.clear.cgColor
            progressLayer.strokeColor = (completionRate >= 1.0 ? UIColor.successGreen : UIColor.primary).cgColor
            progressLayer.lineWidth = ringWidth
            progressLayer.lineCap = .round
            progressLayer.strokeEnd = totalParagraphs > 0 ? CGFloat(completionRate) : 0
            ringView.layer.addSublayer(progressLayer)

            // Center label: completion percentage
            let rateLabel = UILabel()
            rateLabel.text = totalParagraphs > 0 ? "\(Int(completionRate * 100))%" : "--"
            rateLabel.font = UIFont.systemFont(ofSize: 18, weight: .bold)
            rateLabel.textColor = .textPrimary
            rateLabel.textAlignment = .center
            rateLabel.tag = 1002
            rateLabel.translatesAutoresizingMaskIntoConstraints = false
            ringView.addSubview(rateLabel)

            // Caption below ring
            let rateCaption = UILabel()
            rateCaption.text = totalParagraphs > 0 ? "\(readCount)/\(totalParagraphs) 段" : "完成率"
            rateCaption.font = UIFont.systemFont(ofSize: 11)
            rateCaption.textColor = .textSecondary
            rateCaption.textAlignment = .center
            rateCaption.tag = 1003
            rateCaption.translatesAutoresizingMaskIntoConstraints = false
            completionContainer.addSubview(rateCaption)

            // --- Right: Total Score Circle ---
            let scoreCircleSize: CGFloat = 80

            let scoreContainer = UIView()
            scoreContainer.tag = 1010
            scoreContainer.translatesAutoresizingMaskIntoConstraints = false

            let scoreCircle = UIView()
            scoreCircle.layer.cornerRadius = scoreCircleSize / 2
            scoreCircle.backgroundColor = scoreCircleColor(score: totalScore, hasData: hasData)
            scoreCircle.tag = 1011
            scoreCircle.translatesAutoresizingMaskIntoConstraints = false
            scoreContainer.addSubview(scoreCircle)

            let scoreNumberLabel = UILabel()
            scoreNumberLabel.text = hasData ? "\(Int(totalScore))" : "--"
            scoreNumberLabel.font = UIFont.systemFont(ofSize: 26, weight: .bold)
            scoreNumberLabel.textColor = .white
            scoreNumberLabel.textAlignment = .center
            scoreNumberLabel.tag = 1012
            scoreNumberLabel.translatesAutoresizingMaskIntoConstraints = false
            scoreCircle.addSubview(scoreNumberLabel)

            let unitLabel = UILabel()
            unitLabel.text = "分"
            unitLabel.font = UIFont.systemFont(ofSize: 11)
            unitLabel.textColor = UIColor.white.withAlphaComponent(0.8)
            unitLabel.textAlignment = .center
            unitLabel.tag = 1013
            unitLabel.translatesAutoresizingMaskIntoConstraints = false
            scoreCircle.addSubview(unitLabel)

            let scoreCaption = UILabel()
            scoreCaption.text = "总得分"
            scoreCaption.font = UIFont.systemFont(ofSize: 11)
            scoreCaption.textColor = .textSecondary
            scoreCaption.textAlignment = .center
            scoreCaption.tag = 1014
            scoreCaption.translatesAutoresizingMaskIntoConstraints = false
            scoreContainer.addSubview(scoreCaption)

            // Add to stack
            containerStack.addArrangedSubview(completionContainer)
            containerStack.addArrangedSubview(scoreContainer)

            // Layout
            let containerHeight: CGFloat = ringSize + 26 // ring + caption spacing
            NSLayoutConstraint.activate([
                containerStack.topAnchor.constraint(equalTo: cell.contentView.topAnchor, constant: 14),
                containerStack.bottomAnchor.constraint(equalTo: cell.contentView.bottomAnchor, constant: -14),
                containerStack.centerXAnchor.constraint(equalTo: cell.contentView.centerXAnchor),
                containerStack.widthAnchor.constraint(lessThanOrEqualTo: cell.contentView.widthAnchor, constant: -32),

                completionContainer.widthAnchor.constraint(equalToConstant: ringSize),
                completionContainer.heightAnchor.constraint(equalToConstant: containerHeight),

                ringView.topAnchor.constraint(equalTo: completionContainer.topAnchor),
                ringView.centerXAnchor.constraint(equalTo: completionContainer.centerXAnchor),
                ringView.widthAnchor.constraint(equalToConstant: ringSize),
                ringView.heightAnchor.constraint(equalToConstant: ringSize),

                rateLabel.centerXAnchor.constraint(equalTo: ringView.centerXAnchor),
                rateLabel.centerYAnchor.constraint(equalTo: ringView.centerYAnchor),

                rateCaption.centerXAnchor.constraint(equalTo: completionContainer.centerXAnchor),
                rateCaption.topAnchor.constraint(equalTo: ringView.bottomAnchor, constant: 2),

                scoreContainer.widthAnchor.constraint(equalToConstant: scoreCircleSize),
                scoreContainer.heightAnchor.constraint(equalToConstant: containerHeight),

                scoreCircle.topAnchor.constraint(equalTo: scoreContainer.topAnchor, constant: (ringSize - scoreCircleSize) / 2),
                scoreCircle.centerXAnchor.constraint(equalTo: scoreContainer.centerXAnchor),
                scoreCircle.widthAnchor.constraint(equalToConstant: scoreCircleSize),
                scoreCircle.heightAnchor.constraint(equalToConstant: scoreCircleSize),

                scoreNumberLabel.centerXAnchor.constraint(equalTo: scoreCircle.centerXAnchor),
                scoreNumberLabel.centerYAnchor.constraint(equalTo: scoreCircle.centerYAnchor, constant: -6),

                unitLabel.topAnchor.constraint(equalTo: scoreNumberLabel.bottomAnchor, constant: -2),
                unitLabel.centerXAnchor.constraint(equalTo: scoreCircle.centerXAnchor),

                scoreCaption.centerXAnchor.constraint(equalTo: scoreContainer.centerXAnchor),
                scoreCaption.topAnchor.constraint(equalTo: scoreContainer.topAnchor, constant: ringSize + 2)
            ])

            return cell

        case 1:
            let cell = tableView.dequeueReusableCell(withIdentifier: "ExpectedTextCell", for: indexPath)
            cell.selectionStyle = .none

            if task.expectedTexts.isEmpty {
                cell.textLabel?.text = "暂无文本，点击右上角 + 添加"
                cell.textLabel?.textColor = .textTertiary
                cell.accessoryType = .none
                cell.detailTextLabel?.text = nil
            } else {
                let text = task.expectedTexts[indexPath.row]
                cell.textLabel?.text = text.truncated(80)
                cell.textLabel?.textColor = .textPrimary
                cell.textLabel?.numberOfLines = 2

                // Show completion status
                let readIndices = Set(task.sessions.map { $0.expectedTextIndex })
                if readIndices.contains(indexPath.row) {
                    cell.accessoryType = .checkmark
                    cell.tintColor = .successGreen
                } else {
                    cell.accessoryType = .none
                }
            }
            return cell

        case 2:
            let cell: UITableViewCell
            if let reused = tableView.dequeueReusableCell(withIdentifier: "HistoryCell") {
                cell = reused
            } else {
                cell = UITableViewCell(style: .subtitle, reuseIdentifier: "HistoryCell")
            }
            let session = task.sessions[indexPath.row]
            let textIndex = session.expectedTextIndex
            let preview = textIndex < task.expectedTexts.count ? task.expectedTexts[textIndex].truncated(40) : "未知文本"
            cell.textLabel?.text = "\(indexPath.row + 1). \(preview)"
            cell.textLabel?.numberOfLines = 1
            cell.textLabel?.textColor = .textPrimary

            if let result = session.result {
                cell.detailTextLabel?.text = "得分: \(Int(result.score))%"
                cell.detailTextLabel?.textColor = result.score >= 80 ? .successGreen : .errorRed
            }

            cell.accessoryType = .disclosureIndicator
            return cell

        default:
            return UITableViewCell()
        }
    }

    // MARK: - Score Computation
    /// Computes total score: for each expected text paragraph, find the highest
    /// historical score across all sessions. Average those highest scores.
    /// Unread paragraphs are excluded from the average.
    private func computeTotalScore(for task: ReadingTask) -> Double {
        guard !task.expectedTexts.isEmpty else { return 0.0 }

        var highestScores: [Double] = []
        for index in task.expectedTexts.indices {
            let sessionsForIndex = task.sessions.filter { $0.expectedTextIndex == index }
            let scores = sessionsForIndex.compactMap { $0.result?.score }
            if let maxScore = scores.max() {
                highestScores.append(maxScore)
            }
            // Unread paragraphs are not included
        }

        guard !highestScores.isEmpty else { return 0.0 }
        return highestScores.reduce(0.0, +) / Double(highestScores.count)
    }

    /// Returns the color for the score circle based on score value.
    private func scoreCircleColor(score: Double, hasData: Bool) -> UIColor {
        guard hasData else { return .textTertiary }
        if score >= 90 { return .successGreen }
        if score >= 70 { return .primary }
        if score >= 50 { return .warningOrange }
        return .errorRed
    }
}

// MARK: - UITableViewDelegate
extension TaskDetailViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if indexPath.section == 0 {
            return 140 // Overview circles (ring + score circle + captions)
        }
        return UITableView.automaticDimension
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        guard let task = task else { return }

        switch indexPath.section {
        case 0:
            // Overview - no action
            break
        case 1 where !task.expectedTexts.isEmpty:
            // Edit expected text
            let text = task.expectedTexts[indexPath.row]
            let inputVC = TextInputViewController(initialText: text)
            inputVC.onSave = { [weak self] newText in
                guard let self = self, let task = self.task else { return }
                task.expectedTexts[indexPath.row] = newText
                TaskManager.shared.updateTask(task)
                self.tableView.reloadData()
            }
            let nav = UINavigationController(rootViewController: inputVC)
            present(nav, animated: true)
        case 2:
            // View result
            let session = task.sessions[indexPath.row]
            if let result = session.result {
                let resultVC = ResultViewController(result: result)
                navigationController?.pushViewController(resultVC, animated: true)
            }
        default:
            break
        }
    }

    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return indexPath.section == 1 && !(task?.expectedTexts.isEmpty ?? true)
    }

    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete, indexPath.section == 1 {
            guard let task = task else { return }
            task.expectedTexts.remove(at: indexPath.row)
            TaskManager.shared.updateTask(task)
            tableView.reloadData()
            updateStartButton()
        }
    }

    func tableView(_ tableView: UITableView, editActionsForRowAt indexPath: IndexPath) -> [UITableViewRowAction]? {
        guard indexPath.section == 1 else { return nil }

        let deleteAction = UITableViewRowAction(style: .destructive, title: "删除") { [weak self] _, _ in
            guard let self = self, let task = self.task else { return }
            task.expectedTexts.remove(at: indexPath.row)
            TaskManager.shared.updateTask(task)
            self.tableView.reloadData()
            self.updateStartButton()
        }

        return [deleteAction]
    }
}

// MARK: - Text Input View Controller (inline)
/// Simple multi-line text input view controller.
final class TextInputViewController: UIViewController {

    private let textView = UITextView()
    var initialText: String = ""
    var onSave: ((String) -> Void)?

    init(initialText: String = "") {
        self.initialText = initialText
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .background
        title = initialText.isEmpty ? "输入文本" : "编辑文本"

        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelTapped))
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .save, target: self, action: #selector(saveTapped))

        textView.font = UIFont.systemFont(ofSize: 16)
        textView.text = initialText
        textView.backgroundColor = .cardBackground
        textView.layer.cornerRadius = 8
        textView.layer.borderWidth = 0.5
        textView.layer.borderColor = UIColor.separator.cgColor
        textView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(textView)

        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: compatSafeAreaTop, constant: 16),
            textView.bottomAnchor.constraint(equalTo: compatSafeAreaBottom, constant: -16),
            textView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            textView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16)
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if initialText.isEmpty {
            textView.becomeFirstResponder()
        }
    }

    @objc private func cancelTapped() {
        dismiss(animated: true)
    }

    @objc private func saveTapped() {
        let text = textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            showAlert(title: "提示", message: "请输入文本内容")
            return
        }
        onSave?(text)
        dismiss(animated: true)
    }
}
