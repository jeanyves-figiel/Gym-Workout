import SwiftUI

struct VerifyEmailView: View {
    let email: String
    @Environment(AppModel.self) private var model
    @State private var code = ""
    @State private var task = FormTask()
    @State private var resent = false

    var body: some View {
        AuthScreen(title: "Verify email") {
            AccountHeader(symbol: "envelope.badge.fill", title: "Check your email",
                          subtitle: "We sent a code to \(email). It expires in 15 minutes.",
                          gradient: AccountTint.email)
            AccountField(label: "6-digit code") {
                TextField("123456", text: $code)
                    .textContentType(.oneTimeCode)
                    .keyboardType(.numberPad)
                    .font(Theme.display(28).monospacedDigit())
                    .tracking(6)
                    .accessibilityLabel("6-digit code")
                    .onChange(of: code) { _, new in
                        code = String(new.filter(\.isNumber).prefix(6))
                        if code.count == 6 { submit() }
                    }
            }
            ErrorText(message: task.error)
            LimeActionButton(title: "Verify", busy: task.busy, disabled: code.count != 6, action: submit)
                .padding(.top, 6)
            AccountPillButton(title: resent ? "Code sent" : "Resend code") {
                Task {
                    try? await model.api.resendVerification(email: email)
                    resent = true
                }
            }
            .disabled(resent)
            AccountNote(text: "No email? Check spam, or resend the code.")
        }
    }

    private func submit() {
        task.run {
            let user = try await model.api.verifyEmail(email: email, code: code)
            await model.didAuthenticate(user)
        }
    }
}
