import SwiftUI
import UIKit

/// Captures hardware keyboard presses (Bluetooth or Smart Keyboard) so W/A/S/D
/// actually drives the robot while the phone is in the app.
///
/// SwiftUI's onKeyPress needs iOS 17.4, so this uses UIKit's pressesBegan /
/// pressesEnded which works from iOS 16 and also receives key repeats.
struct HardwareKeyboardView: UIViewRepresentable {
    var onPress: (Character) -> Void
    var onRelease: (Character) -> Void
    /// Increment to re-claim first responder after the user finishes typing.
    var focusToken: Int

    func makeUIView(context: Context) -> KeyboardCaptureUIView {
        let view = KeyboardCaptureUIView()
        view.onPress = onPress
        view.onRelease = onRelease
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        context.coordinator.lastFocusToken = focusToken
        return view
    }

    func updateUIView(_ uiView: KeyboardCaptureUIView, context: Context) {
        uiView.onPress = onPress
        uiView.onRelease = onRelease
        // Only take focus when explicitly requested; stealing it on every
        // update would dismiss the address text field while typing.
        if context.coordinator.lastFocusToken != focusToken {
            context.coordinator.lastFocusToken = focusToken
            uiView.claimFocus()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var lastFocusToken = 0
    }
}

final class KeyboardCaptureUIView: UIView {
    var onPress: ((Character) -> Void)?
    var onRelease: ((Character) -> Void)?
    private var pressedKeys: Set<String> = []

    override var canBecomeFirstResponder: Bool { true }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { claimFocus() }
        else { resignFirstResponder() }
    }

    func claimFocus() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window != nil, !self.isFirstResponder else { return }
            self.becomeFirstResponder()
        }
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handled = false
        for press in presses {
            guard let characters = press.key?.charactersIgnoringModifiers, !characters.isEmpty else { continue }
            let key = String(characters)
            guard !pressedKeys.contains(key) else { continue }
            pressedKeys.insert(key)
            onPress?(characters.first!)
            handled = true
        }
        if !handled { super.pressesBegan(presses, with: event) }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var handled = false
        for press in presses {
            guard let characters = press.key?.charactersIgnoringModifiers, !characters.isEmpty else { continue }
            let key = String(characters)
            guard pressedKeys.remove(key) != nil else { continue }
            onRelease?(characters.first!)
            handled = true
        }
        if !handled { super.pressesEnded(presses, with: event) }
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            if let characters = press.key?.charactersIgnoringModifiers, !characters.isEmpty {
                pressedKeys.remove(String(characters))
                onRelease?(characters.first!)
            }
        }
        super.pressesCancelled(presses, with: event)
    }
}
