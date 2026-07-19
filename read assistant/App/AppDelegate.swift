import UIKit

// MARK: - App Delegate
/// Main application delegate for the Reading Assistant app.
/// Targets iOS 10.0+. Uses the classic UIApplicationDelegate pattern.
@UIApplicationMain
final class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

        // Register UserDefaults defaults
        UserDefaults.standard.register(defaults: [
            "auto_split_by_newline_enabled": true
        ])

        // Initialize wrong answer book cache from existing reading history
        WrongAnswerBookManager.shared.syncWrongAnswers()

        // Initialize window (no UISceneDelegate on iOS 10)
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.backgroundColor = .background

        // --- Tab 1: Home (Task List) ---
        let taskListVC = TaskListViewController()
        let homeNav = UINavigationController(rootViewController: taskListVC)
        homeNav.navigationBar.barTintColor = .cardBackground
        homeNav.navigationBar.tintColor = .primary
        homeNav.navigationBar.titleTextAttributes = [
            NSAttributedString.Key.foregroundColor: UIColor.textPrimary
        ]
        homeNav.navigationBar.isTranslucent = false
        homeNav.tabBarItem = UITabBarItem(
            title: "首页",
            image: Self.emojiIcon("📖"),
            tag: 0
        )

        // --- Tab 2: Rewards ---
        let rewardsVC = RewardsViewController()
        let rewardsNav = UINavigationController(rootViewController: rewardsVC)
        rewardsNav.navigationBar.barTintColor = .cardBackground
        rewardsNav.navigationBar.tintColor = .primary
        rewardsNav.navigationBar.titleTextAttributes = [
            NSAttributedString.Key.foregroundColor: UIColor.textPrimary
        ]
        rewardsNav.navigationBar.isTranslucent = false
        rewardsNav.tabBarItem = UITabBarItem(
            title: "奖励",
            image: Self.emojiIcon("🎁"),
            tag: 1
        )

        // --- Tab 3: Study Tools (Wrong Answer Book & Quiz) ---
        let studyVC = WordChallengeMenuViewController()
        let studyNav = UINavigationController(rootViewController: studyVC)
        studyNav.navigationBar.barTintColor = .cardBackground
        studyNav.navigationBar.tintColor = .primary
        studyNav.navigationBar.titleTextAttributes = [
            NSAttributedString.Key.foregroundColor: UIColor.textPrimary
        ]
        studyNav.navigationBar.isTranslucent = false
        studyNav.tabBarItem = UITabBarItem(
            title: "学习",
            image: Self.emojiIcon("📝"),
            tag: 2
        )

        // --- Tab 4: Settings ---
        let settingsVC = SettingsViewController()
        let settingsNav = UINavigationController(rootViewController: settingsVC)
        settingsNav.navigationBar.barTintColor = .cardBackground
        settingsNav.navigationBar.tintColor = .primary
        settingsNav.navigationBar.titleTextAttributes = [
            NSAttributedString.Key.foregroundColor: UIColor.textPrimary
        ]
        settingsNav.navigationBar.isTranslucent = false
        settingsNav.tabBarItem = UITabBarItem(
            title: "设置",
            image: Self.emojiIcon("⚙️"),
            tag: 3
        )

        // --- Tab Bar Controller ---
        let tabBarController = UITabBarController()
        tabBarController.viewControllers = [homeNav, rewardsNav, studyNav, settingsNav]
        tabBarController.tabBar.barTintColor = .cardBackground
        tabBarController.tabBar.tintColor = .primary
        tabBarController.tabBar.isTranslucent = false

        window?.rootViewController = tabBarController
        window?.makeKeyAndVisible()

        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state.
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Use this method to release shared resources, save user data, etc.
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called as part of the transition from the background to the active state.
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while inactive.
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate.
    }

    // MARK: - Tab Bar Icons (iOS 10 compatible, rendered from emoji)

    /// Renders an emoji character into a template UIImage for tab bar use.
    private static func emojiIcon(_ emoji: String) -> UIImage {
        let size = CGSize(width: 24, height: 24)
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        let rect = CGRect(origin: .zero, size: size)
        (emoji as NSString).draw(in: rect, withAttributes: [
            .font: UIFont.systemFont(ofSize: 22)
        ])
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image?.withRenderingMode(.alwaysTemplate) ?? UIImage()
    }
}
