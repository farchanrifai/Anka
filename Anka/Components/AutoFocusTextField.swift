import SwiftUI
import UIKit

/// UIKit-backed text field that claims first responder **during** its window
/// attachment phase (`didMoveToWindow`). When this view is presented inside a
/// SwiftUI sheet with `.navigationTransition(.zoom(...))`, the first-responder
/// claim happens early enough in the present animation that iOS's animator
/// schedules the keyboard slide on the same frame as the sheet zoom — Mail's
/// exact compose-button timing.
///
/// **Why we can't do this with SwiftUI `TextField` + `@FocusState`:**
/// SwiftUI's `@FocusState` → `UITextField.becomeFirstResponder()` translation
/// runs on a later runloop tick relative to the sheet appearance animation.
/// By the time the responder claim reaches UIKit, the sheet animation is
/// already partway through (or done), so iOS treats the keyboard as a
/// separate, sequential animation. The user sees: sheet zooms → done →
/// keyboard slides up (delayed, sequential).
///
/// With this UIKit field, `becomeFirstResponder()` is called inline inside
/// `didMoveToWindow`, which fires while the sheet animation is in progress.
/// Result: keyboard animates in lockstep with the sheet zoom.
///
/// The view still bridges to a SwiftUI `@FocusState` binding so the rest
/// of the app's focus logic (e.g. submit-to-amount, refocus after closing
/// the date picker) keeps working — it just isn't relied on for the
/// initial Mail-style claim.
struct AutoFocusTextField<FocusValue: Hashable>: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var font: UIFont

    /// Bridges SwiftUI's `@FocusState` to the underlying UITextField's
    /// first-responder state. Pass `(binding, myValue)` to integrate.
    var focusBinding: FocusState<FocusValue?>.Binding?
    var focusValue: FocusValue?

    /// Auto-claim first responder on first window attachment. Only the
    /// initial appearance — re-using the field later doesn't re-claim.
    var autoFocusOnAppear: Bool = true

    var keyboardType: UIKeyboardType = .default
    var returnKeyType: UIReturnKeyType = .default
    var autocapitalization: UITextAutocapitalizationType = .sentences
    var autocorrection: UITextAutocorrectionType = .no

    var onChange: ((String) -> Void)? = nil
    var onSubmit: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> _AutoFocusUITextField {
        let tf = _AutoFocusUITextField()
        tf.autoFocusOnAppear = autoFocusOnAppear

        tf.placeholder = placeholder
        tf.font = font
        tf.textColor = UIColor.label
        tf.keyboardType = keyboardType
        tf.returnKeyType = returnKeyType
        tf.autocapitalizationType = autocapitalization
        tf.autocorrectionType = autocorrection
        tf.tintColor = UIColor.tintColor

        tf.delegate = context.coordinator
        tf.addTarget(
            context.coordinator,
            action: #selector(Coordinator.textChanged(_:)),
            for: .editingChanged
        )

        // Setting text imperatively the first time keeps SwiftUI's
        // updateUIView path from spuriously notifying onChange for the
        // initial value.
        tf.text = text

        return tf
    }

    func updateUIView(_ tf: _AutoFocusUITextField, context: Context) {
        // Stash latest config so the Coordinator's delegate callbacks see
        // current bindings/closures, not stale ones from `makeUIView`.
        context.coordinator.parent = self

        // Sync external binding writes back to the field (e.g.
        // `vm.loadExisting(tx)` seeds descriptionText). The guard is critical
        // because re-assigning `tf.text` during active editing resets the
        // cursor and can interact badly with input-handling.
        if tf.text != text {
            tf.text = text
        }

        // NOTE: `placeholder` and `font` are intentionally set ONLY in
        // makeUIView. They don't change at runtime for this field, and
        // re-assigning them on every render caused a regression where the
        // keyboard closed after one keystroke. UIFont equality is unreliable
        // (`UIFont.systemFont(...)` can return distinct instances), so the
        // `!=` check often fired and the spurious property write happened
        // during UIKit's input-handling pass — corrupting first-responder
        // state. If these ever need to be runtime-configurable, gate the
        // re-assignment on `!tf.isFirstResponder`.

        // Sync SwiftUI @FocusState → UIKit first responder, but ONLY in the
        // grant direction. We never force-resign here:
        //
        // - UIKit already resigns the field automatically when another
        //   responder takes over (e.g. focusedField = .amount → amountField's
        //   .focused() bridge → becomeFirstResponder on the amount UITextField
        //   → UIKit auto-resigns this one).
        // - User-driven dismissal (tap-outside, swipe-down) also resigns
        //   without our involvement.
        // - Force-resigning here on a transient `focusedField != .description`
        //   (which happens momentarily during some SwiftUI re-renders,
        //   especially when sparkleActive flips after the first char) would
        //   tear down focus the user explicitly wanted. That was the
        //   "keyboard closes after one character" bug.
        if let binding = focusBinding, let value = focusValue {
            let shouldBeFocused = (binding.wrappedValue == value)
            if shouldBeFocused && !tf.isFirstResponder {
                tf.becomeFirstResponder()
            }
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: AutoFocusTextField

        init(_ parent: AutoFocusTextField) {
            self.parent = parent
        }

        @objc func textChanged(_ tf: UITextField) {
            let newText = tf.text ?? ""
            // Forward to SwiftUI binding + onChange callback.
            parent.text = newText
            parent.onChange?(newText)
        }

        func textFieldDidBeginEditing(_ tf: UITextField) {
            // Sync UIKit → SwiftUI @FocusState so other UI that observes
            // the FocusState (e.g. animation suppression) sees the change.
            if let binding = parent.focusBinding, let value = parent.focusValue {
                if binding.wrappedValue != value {
                    binding.wrappedValue = value
                }
            }
        }

        func textFieldDidEndEditing(_ tf: UITextField) {
            // Defer the nil-set: if this `endEditing` was a transient UIKit
            // internal (mid-render layout churn, brief window detach), the
            // field will be back to first-responder by the next runloop tick.
            // Only commit the nil to the binding if we're STILL not focused
            // after that grace period — preserves real user-driven resigns
            // (tap-outside, return key) while ignoring spurious blips.
            guard let binding = parent.focusBinding,
                  let value = parent.focusValue,
                  binding.wrappedValue == value else { return }
            DispatchQueue.main.async { [weak tf, weak self] in
                guard let tf, let self else { return }
                if !tf.isFirstResponder, binding.wrappedValue == value {
                    binding.wrappedValue = nil
                }
                _ = self  // silence unused-warning; we keep the capture intentional
            }
        }

        func textFieldShouldReturn(_ tf: UITextField) -> Bool {
            parent.onSubmit?()
            return true
        }
    }
}

/// The actual UITextField subclass. Calling `becomeFirstResponder()` inside
/// `didMoveToWindow` is the critical lifecycle hook — it fires while the
/// sheet's zoom animation is still in progress, so iOS coordinates the
/// keyboard slide with the sheet zoom on the same animation frame.
final class _AutoFocusUITextField: UITextField {
    var autoFocusOnAppear: Bool = false
    private var didAutoFocus = false

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, autoFocusOnAppear, !didAutoFocus else { return }
        didAutoFocus = true
        // Synchronous — iOS schedules the keyboard animation against the
        // active sheet present animation.
        becomeFirstResponder()
    }
}
