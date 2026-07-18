import UIKit

// MARK: - App Delegate
/// Main application delegate for the Reading Assistant app.
/// Targets iOS 10.0+. Uses the classic UIApplicationDelegate pattern.
@UIApplicationMain
final class AppDelegate: UIResponder, UIApplicationDelegate {

    var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

        // Configure Bailian OCR API key.
        // Replace with your key from https://bailian.console.aliyun.com → API-KEY 管理
        if BailianOCRService.defaultAPIKey.isEmpty {
            BailianOCRService.defaultAPIKey = ""  // ← Paste your API key here
        }

        // Initialize window (no UISceneDelegate on iOS 10)
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.backgroundColor = .background

        // Initialize root view controller
        let taskListVC = TaskListViewController()
        let navigationController = UINavigationController(rootViewController: taskListVC)
        navigationController.navigationBar.barTintColor = .cardBackground
        navigationController.navigationBar.tintColor = .primary
        navigationController.navigationBar.titleTextAttributes = [
            NSAttributedString.Key.foregroundColor: UIColor.textPrimary
        ]
        navigationController.navigationBar.isTranslucent = false

        window?.rootViewController = navigationController
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
}
