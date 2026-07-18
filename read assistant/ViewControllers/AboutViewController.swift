import UIKit

// MARK: - About View Controller
/// Displays app version and information.
final class AboutViewController: UIViewController {

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    // MARK: - UI Setup
    private func setupUI() {
        title = "关于"
        view.backgroundColor = .background

        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        let contentView = UIView()
        contentView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(contentView)

        // App Icon
        let iconView = UIImageView()
        if #available(iOS 13.0, *) {
            iconView.image = UIImage(named: "AppIcon") ?? UIImage(systemName: "book.fill")
        } else {
            // Fallback on earlier versions
        }
        iconView.tintColor = .primary
        iconView.contentMode = .scaleAspectFit
        iconView.layer.cornerRadius = 20
        iconView.clipsToBounds = true
        iconView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(iconView)

        // App Name
        let nameLabel = UILabel()
        nameLabel.text = "阅读助手"
        nameLabel.font = UIFont.boldSystemFont(ofSize: 24)
        nameLabel.textColor = .textPrimary
        nameLabel.textAlignment = .center
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(nameLabel)

        // Version
        let versionLabel = UILabel()
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        versionLabel.text = "版本 \(version) (Build \(build))"
        versionLabel.font = UIFont.systemFont(ofSize: 14)
        versionLabel.textColor = .textSecondary
        versionLabel.textAlignment = .center
        versionLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(versionLabel)

        // Description
        let descLabel = UILabel()
        descLabel.text = "阅读助手是一款帮助用户提升阅读能力的应用。\n通过语音识别和AI评分，帮助您准确、流利地朗读文本。"
        descLabel.font = UIFont.systemFont(ofSize: 15)
        descLabel.textColor = .textSecondary
        descLabel.textAlignment = .center
        descLabel.numberOfLines = 0
        descLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(descLabel)

        // Separator
        let separator = UIView()
        separator.backgroundColor = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(separator)

        // Copyright
        let copyrightLabel = UILabel()
        copyrightLabel.text = "© 2025 阅读助手"
        copyrightLabel.font = UIFont.systemFont(ofSize: 12)
        copyrightLabel.textColor = .textTertiary
        copyrightLabel.textAlignment = .center
        copyrightLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(copyrightLabel)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            contentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),

            iconView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 50),
            iconView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 80),
            iconView.heightAnchor.constraint(equalToConstant: 80),

            nameLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 16),
            nameLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),

            versionLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 8),
            versionLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),

            descLabel.topAnchor.constraint(equalTo: versionLabel.bottomAnchor, constant: 30),
            descLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 40),
            descLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -40),

            separator.topAnchor.constraint(equalTo: descLabel.bottomAnchor, constant: 40),
            separator.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 40),
            separator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -40),
            separator.heightAnchor.constraint(equalToConstant: 0.5),

            copyrightLabel.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 16),
            copyrightLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            copyrightLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -30)
        ])
    }
}
