import AppKit
import SwiftUI

enum AddressToolbarMetrics {
    static let controlSize: CGFloat = 34
    static let symbolSize: CGFloat = 18
}

struct BrowserAddressField: NSViewRepresentable {
    let text: String
    let placeholder: String?
    @Binding var focused: Bool
    let focusRequest: Int
    let edited: (String) -> Void
    let handle: (Selector) -> Bool

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: BrowserAddressField
        var appliedFocusRequest = 0

        init(parent: BrowserAddressField) {
            self.parent = parent
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            parent.focused = true
        }

        func controlTextDidChange(_ notification: Notification) {
            if let field = notification.object as? NSTextField {
                parent.edited(field.stringValue)
            }
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            parent.focused = false
        }

        func control(_ control: NSControl, textView: NSTextView,
                     doCommandBy commandSelector: Selector) -> Bool {
            parent.handle(commandSelector)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.placeholderString = placeholder
        field.setAccessibilityLabel(placeholder ?? "Адресная строка")
        field.isBezeled = false
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.lineBreakMode = .byTruncatingTail
        field.delegate = context.coordinator
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        field.placeholderString = placeholder
        field.setAccessibilityLabel(placeholder ?? "Адресная строка")
        if field.currentEditor() == nil, field.stringValue != text {
            field.stringValue = text
        }
        if coordinator.appliedFocusRequest != focusRequest {
            coordinator.appliedFocusRequest = focusRequest
            DispatchQueue.main.async { [weak field, weak coordinator] in
                guard coordinator?.parent.focused == true else { return }
                field?.selectText(nil)
            }
        } else if !focused, field.currentEditor() != nil {
            DispatchQueue.main.async { [weak field, weak coordinator] in
                guard let field, let coordinator, !coordinator.parent.focused,
                      field.currentEditor() != nil else { return }
                field.window?.makeFirstResponder(nil)
                field.stringValue = coordinator.parent.text
            }
        }
    }
}

