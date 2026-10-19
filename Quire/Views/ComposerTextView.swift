import SwiftUI
import UIKit

/// The message box's text. SwiftUI's growing text field jumps up and down once its text passes the
/// line limit and it starts scrolling inside itself; this one measures its own height, grows a line
/// at a time up to `maxLines`, then scrolls inside with the caret kept in view.
///
/// It also sends on a hardware keyboard's Return (when that's on in settings; Shift-Return still
/// starts a new line), and takes a pasted image as an attachment instead of refusing it.
struct ComposerTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var focused: Bool
    var maxLines = 8
    var sendOnHardwareReturn = false
    var hint: String = ""
    var onSend: () -> Void = {}
    var onPasteImage: (UIImage) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> ComposerUITextView {
        let tv = ComposerUITextView()
        tv.delegate = context.coordinator
        tv.font = .preferredFont(forTextStyle: .body)
        tv.adjustsFontForContentSizeCategory = true
        tv.textColor = UIColor(Color.qInk)
        tv.tintColor = UIColor(Color.qAccent)
        tv.backgroundColor = .clear
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.isScrollEnabled = false
        tv.alwaysBounceVertical = false
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tv.setContentHuggingPriority(.defaultLow, for: .horizontal)
        tv.accessibilityLabel = "Message"
        tv.text = text
        return tv
    }

    func updateUIView(_ tv: ComposerUITextView, context: Context) {
        context.coordinator.parent = self
        tv.sendOnReturn = sendOnHardwareReturn
        tv.onReturn = onSend
        tv.onPasteImage = onPasteImage
        tv.accessibilityHint = hint
        // Text set from outside (a starter, sending, a restored draft). Never while the keyboard is
        // composing (Japanese, Chinese, …), which would throw that composition away.
        if tv.text != text, tv.markedTextRange == nil {
            tv.text = text
            if tv.isScrollEnabled { tv.scrollRangeToVisible(tv.selectedRange) }
        }
        // Focus changes go through the run loop: taking or giving up the keyboard calls back into
        // the binding, which mustn't happen in the middle of a view update.
        if focused, !tv.isFirstResponder {
            DispatchQueue.main.async { if tv.window != nil { tv.becomeFirstResponder() } }
        } else if !focused, tv.isFirstResponder {
            DispatchQueue.main.async { tv.resignFirstResponder() }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView tv: ComposerUITextView, context: Context) -> CGSize? {
        let width = proposal.width ?? (tv.bounds.width > 0 ? tv.bounds.width : 300)
        guard width.isFinite, width > 0 else { return nil }
        let line = (tv.font ?? .preferredFont(forTextStyle: .body)).lineHeight
        let fitted = ceil(tv.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height)
        let limit = ceil(line * CGFloat(maxLines))
        let scrolls = fitted > limit + 0.5
        if tv.isScrollEnabled != scrolls { tv.isScrollEnabled = scrolls }
        return CGSize(width: width, height: min(max(fitted, ceil(line)), limit))
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: ComposerTextView

        init(_ parent: ComposerTextView) { self.parent = parent }

        func textViewDidChange(_ tv: UITextView) {
            parent.text = tv.text
            if tv.isScrollEnabled { tv.scrollRangeToVisible(tv.selectedRange) }
        }

        func textViewDidBeginEditing(_ tv: UITextView) {
            if !parent.focused { parent.focused = true }
        }

        func textViewDidEndEditing(_ tv: UITextView) {
            if parent.focused { parent.focused = false }
        }
    }
}

final class ComposerUITextView: UITextView {
    var sendOnReturn = false
    var onReturn: (() -> Void)?
    var onPasteImage: ((UIImage) -> Void)?

    /// Return on a hardware keyboard sends. Key commands only come from hardware keyboards, so the
    /// on-screen Return still makes a new line; and while an input method is composing, Return is
    /// left to it.
    override var keyCommands: [UIKeyCommand]? {
        guard sendOnReturn, markedTextRange == nil else { return super.keyCommands }
        let send = UIKeyCommand(input: "\r", modifierFlags: [], action: #selector(hardwareReturn))
        send.wantsPriorityOverSystemBehavior = true
        return [send] + (super.keyCommands ?? [])
    }

    @objc private func hardwareReturn() { onReturn?() }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(paste(_:)) && UIPasteboard.general.hasImages { return true }
        return super.canPerformAction(action, withSender: sender)
    }

    override func paste(_ sender: Any?) {
        let pb = UIPasteboard.general
        if pb.hasImages, !pb.hasStrings, let image = pb.image {
            onPasteImage?(image)
            return
        }
        super.paste(sender)
    }
}
