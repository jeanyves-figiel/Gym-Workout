import APIClient
import SwiftUI

/// Change (or add) the account email: code sent to the new address, old address notified (#12).
struct ChangeEmailView: View {
    let currentEmail: String?
    let hasPassword: Bool
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var newEmail = ""
    @State private var password = ""
    @State private var code = ""
    @State private var sentTo: String?
    @State private var task = FormTask()
    @State private var resendTask = FormTask()

    private var trimmed: String { newEmail.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let sentTo {
                    AccountHeader(symbol: "envelope.badge.fill", title: "Check your inbox",
                                  subtitle: "Code sent to \(sentTo). It expires in 15 minutes. Check spam if it doesn't arrive.",
                                  gradient: AccountTint.email)
                    AccountField(label: "6-digit code") {
                        TextField("123456", text: $code)
                            .textContentType(.oneTimeCode)
                            .keyboardType(.numberPad)
                            .font(Theme.display(28))
                            .tracking(6)
                            .onChange(of: code) { _, new in code = String(new.filter(\.isNumber).prefix(6)) }
                    }
                    ErrorText(message: task.error)
                    LimeActionButton(title: "Confirm new email", busy: task.busy, disabled: code.count != 6) {
                        task.run {
                            model.user = try await model.api.confirmEmailChange(code: code)
                            dismiss()
                        }
                    }
                    HStack(spacing: 10) {
                        AccountPillButton(title: resendTask.busy ? "Sending…" : "Resend code") {
                            resendTask.run { try await model.api.requestEmailChange(newEmail: sentTo, password: hasPassword ? password : nil) }
                        }
                        .disabled(resendTask.busy)
                        AccountPillButton(title: "Different email") {
                            self.sentTo = nil
                            code = ""
                        }
                    }
                    ErrorText(message: resendTask.error)
                } else {
                    AccountHeader(symbol: "envelope.fill", title: currentEmail == nil ? "Add email" : "Change email",
                                  subtitle: currentEmail.map { "Now: \($0)" } ?? "Sign in with email as well as Apple.",
                                  gradient: AccountTint.email)
                    AccountField(label: "New email") {
                        TextField("you@example.com", text: $newEmail)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    if hasPassword {
                        AccountField(label: "Password") {
                            SecureField("Password", text: $password).textContentType(.password)
                        }
                    }
                    AccountNote(text: "We'll email a 6-digit code to the new address. Your current address will be told about the change.")
                    ErrorText(message: task.error)
                    LimeActionButton(title: "Send code", busy: task.busy,
                                     disabled: !trimmed.contains("@") || (hasPassword && password.isEmpty)) {
                        let email = trimmed
                        task.run {
                            try await model.api.requestEmailChange(newEmail: email, password: hasPassword ? password : nil)
                            sentTo = email
                        }
                    }
                }
            }
            .padding(16)
        }
        .themedForm()
        .navigationTitle(currentEmail == nil ? "Add email" : "Change email")
        .toolbarTitleDisplayMode(.inline)
    }
}
