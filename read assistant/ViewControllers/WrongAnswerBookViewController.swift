import UIKit

// MARK: - Wrong Answer Book View Controller
/// Displays the list of wrong/missed words collected from reading history.
final class WrongAnswerBookViewController: UIViewController {

    // MARK: - Properties
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let emptyStateView = UIView()
    private var items: [WrongAnswerItem] = []

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadData()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Refresh data in case sync happened elsewhere
        loadData()
    }

    // MARK: - Data Loading
    private func loadData() {
        items = WrongAnswerBookManager.shared.wrongAnswers
        tableView.reloadData()
        updateEmptyState()
    }

    // MARK: - UI Setup
    private func setupUI() {
        view.backgroundColor = .background
        title = "错题本"

        // TableView
        tableView.delegate = self
        tableView.dataSource = self
        tableView.backgroundColor = .background
        tableView.separatorColor = .separator
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 80
        tableView.register(WrongAnswerCell.self, forCellReuseIdentifier: "WrongAnswerCell")
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        // Empty state
        setupEmptyState()
    }

    private func setupEmptyState() {
        emptyStateView.translatesAutoresizingMaskIntoConstraints = false
        emptyStateView.isHidden = true
        view.addSubview(emptyStateView)

        let iconLabel = UILabel()
        iconLabel.text = "📝"
        iconLabel.font = UIFont.systemFont(ofSize: 48)
        iconLabel.textAlignment = .center
        iconLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyStateView.addSubview(iconLabel)

        let messageLabel = UILabel()
        messageLabel.text = "还没有错题记录\n完成阅读练习后，读错或遗漏的字词会自动收集到这里"
        messageLabel.font = UIFont.systemFont(ofSize: 15)
        messageLabel.textColor = .textSecondary
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyStateView.addSubview(messageLabel)

        NSLayoutConstraint.activate([
            emptyStateView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyStateView.centerYAnchor.constraint(equalTo: view.centerYAnchor),

            iconLabel.topAnchor.constraint(equalTo: emptyStateView.topAnchor),
            iconLabel.centerXAnchor.constraint(equalTo: emptyStateView.centerXAnchor),

            messageLabel.topAnchor.constraint(equalTo: iconLabel.bottomAnchor, constant: 16),
            messageLabel.leadingAnchor.constraint(equalTo: emptyStateView.leadingAnchor, constant: 32),
            messageLabel.trailingAnchor.constraint(equalTo: emptyStateView.trailingAnchor, constant: -32),
            messageLabel.bottomAnchor.constraint(equalTo: emptyStateView.bottomAnchor)
        ])
    }

    private func updateEmptyState() {
        emptyStateView.isHidden = !items.isEmpty
        tableView.isHidden = items.isEmpty
    }
}

// MARK: - UITableViewDataSource
extension WrongAnswerBookViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "WrongAnswerCell", for: indexPath) as! WrongAnswerCell
        let item = items[indexPath.row]
        cell.configure(with: item)
        return cell
    }
}

// MARK: - UITableViewDelegate
extension WrongAnswerBookViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
    }
}

// MARK: - Wrong Answer Cell
final class WrongAnswerCell: UITableViewCell {

    private let correctLabel = UILabel()
    private let errorTypeLabel = UILabel()
    private let pinyinStack = UIStackView()
    private let correctPinyinLabel = UILabel()
    private let wrongPinyinLabel = UILabel()
    private let wrongTextLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        backgroundColor = .cardBackground
        selectionStyle = .none

        // Correct character
        correctLabel.font = UIFont.systemFont(ofSize: 28, weight: .bold)
        correctLabel.textColor = .textPrimary
        correctLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(correctLabel)

        // Error type badge
        errorTypeLabel.font = UIFont.systemFont(ofSize: 11, weight: .semibold)
        errorTypeLabel.textColor = .white
        errorTypeLabel.textAlignment = .center
        errorTypeLabel.layer.cornerRadius = 4
        errorTypeLabel.clipsToBounds = true
        errorTypeLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(errorTypeLabel)

        // Wrong text
        wrongTextLabel.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        wrongTextLabel.textColor = .errorRed
        wrongTextLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(wrongTextLabel)

        // Pinyin stack
        pinyinStack.axis = .vertical
        pinyinStack.spacing = 2
        pinyinStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(pinyinStack)

        correctPinyinLabel.font = UIFont.systemFont(ofSize: 13)
        correctPinyinLabel.textColor = .successGreen
        pinyinStack.addArrangedSubview(correctPinyinLabel)

        wrongPinyinLabel.font = UIFont.systemFont(ofSize: 13)
        wrongPinyinLabel.textColor = .errorRed
        pinyinStack.addArrangedSubview(wrongPinyinLabel)

        NSLayoutConstraint.activate([
            correctLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            correctLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            correctLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 60),

            errorTypeLabel.leadingAnchor.constraint(equalTo: correctLabel.trailingAnchor, constant: 12),
            errorTypeLabel.topAnchor.constraint(equalTo: correctLabel.topAnchor, constant: 2),
            errorTypeLabel.widthAnchor.constraint(equalToConstant: 40),
            errorTypeLabel.heightAnchor.constraint(equalToConstant: 20),

            wrongTextLabel.leadingAnchor.constraint(equalTo: errorTypeLabel.trailingAnchor, constant: 8),
            wrongTextLabel.centerYAnchor.constraint(equalTo: errorTypeLabel.centerYAnchor),

            pinyinStack.leadingAnchor.constraint(equalTo: correctLabel.trailingAnchor, constant: 12),
            pinyinStack.topAnchor.constraint(equalTo: errorTypeLabel.bottomAnchor, constant: 4),
            pinyinStack.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -16),
            pinyinStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
        ])
    }

    func configure(with item: WrongAnswerItem) {
        correctLabel.text = item.correctText

        switch item.errorType {
        case .wrong:
            errorTypeLabel.text = "读错"
            errorTypeLabel.backgroundColor = .errorRed
        case .missing:
            errorTypeLabel.text = "遗漏"
            errorTypeLabel.backgroundColor = .warningOrange
        case .homophone:
            errorTypeLabel.text = "同音"
            errorTypeLabel.backgroundColor = UIColor(red: 0.6, green: 0.3, blue: 0.8, alpha: 1.0)
        }

        // Wrong text display
        if let wrongText = item.wrongText, !wrongText.isEmpty {
            wrongTextLabel.text = "→ \(wrongText)"
            wrongTextLabel.isHidden = false
        } else {
            wrongTextLabel.isHidden = true
        }

        // Correct pinyin
        correctPinyinLabel.text = "✅ 正确: \(item.correctPinyin)"

        // Wrong pinyin
        if let wp = item.wrongPinyin, !wp.isEmpty, wp != item.correctPinyin {
            wrongPinyinLabel.text = "❌ 错误: \(wp)"
            wrongPinyinLabel.isHidden = false
        } else if item.errorType == .missing {
            wrongPinyinLabel.text = "⚠️ 未读出"
            wrongPinyinLabel.isHidden = false
        } else {
            wrongPinyinLabel.isHidden = true
        }
    }
}
