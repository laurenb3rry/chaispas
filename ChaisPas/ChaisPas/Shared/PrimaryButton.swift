import SwiftUI

/// The app's primary call-to-action: a full-width accent capsule. This chain
/// was duplicated verbatim at ~18 call sites, so it lives here once. The
/// pressable style is part of the control; layout modifiers (padding,
/// identifiers, `.disabled`, `.opacity`) stay at the call site.
struct PrimaryButton: View {
    let title: String
    let action: () -> Void

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(DSType.body.weight(.medium))
                .foregroundStyle(DSColor.background)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(DSColor.accent, in: Capsule())
        }
        .buttonStyle(.pressable)
    }
}
