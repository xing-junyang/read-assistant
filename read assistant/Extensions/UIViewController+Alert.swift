import UIKit

// MARK: - UIViewController Alert Extension
extension UIViewController {

    /// Shows a simple alert with a message and an OK button.
    func showAlert(title: String, message: String, completion: (() -> Void)? = nil) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in
            completion?()
        })
        present(alert, animated: true)
    }

    /// Shows a confirmation alert with Cancel and Confirm buttons.
    func showConfirm(title: String, message: String, confirmTitle: String = "确认", onConfirm: @escaping () -> Void) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: confirmTitle, style: .default) { _ in
            onConfirm()
        })
        present(alert, animated: true)
    }

    /// Shows an action sheet with multiple options.
    func showActionSheet(title: String? = nil, message: String? = nil, actions: [(title: String, style: UIAlertAction.Style, handler: (() -> Void)?)]) {
        let sheet = UIAlertController(title: title, message: message, preferredStyle: .actionSheet)
        for action in actions {
            sheet.addAction(UIAlertAction(title: action.title, style: action.style) { _ in
                action.handler?()
            })
        }
        sheet.addAction(UIAlertAction(title: "取消", style: .cancel))
        // iPad popover support
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = self.view
            popover.sourceRect = CGRect(x: self.view.bounds.midX, y: self.view.bounds.midY, width: 0, height: 0)
        }
        present(sheet, animated: true)
    }

    /// Shows an input alert with a text field.
    func showInputAlert(title: String, placeholder: String = "", initialText: String = "", onConfirm: @escaping (String) -> Void) {
        let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
        alert.addTextField { textField in
            textField.placeholder = placeholder
            textField.text = initialText
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "确认", style: .default) { _ in
            if let text = alert.textFields?.first?.text, !text.isEmpty {
                onConfirm(text)
            }
        })
        present(alert, animated: true)
    }
}
