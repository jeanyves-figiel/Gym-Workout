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
        Form {
            if let sentTo {
                Section {
                    TextField("6-digit code", text: $code)
                        .textContentType(.oneTimeCode)
                        .keyboardType(.numberPad)
                        .onChange(of: code) { _, new in code = String(new.filter(\.isNumber).prefix(6)) }
                } header: {
                    Text("Code sent to \(sentTo)")
                } footer: {
                    VStack(alignment: .leading) {
                        Text("The code expires in 15 minutes. Check your spam folder if it doesn't arrive.")
                        ErrorText(message: task.error)
                    }
                }
                Section {
                    BusyButton(title: "Confirm new email", busy: task.busy, disabled: code.count != 6) {
                        task.run {
                            model.user = try await model.api.confirmEmailChange(code: code)
                            dismiss()
                        }
                    }
                    Button("Resend code") {
                        resendTask.run { try await model.api.requestEmailChange(newEmail: sentTo, password: hasPassword ? password : nil) }
                    }
                    .disabled(resendTask.busy)
                    Button("Use a different email") {
                        self.sentTo = nil
                        code = ""
                    }
                    ErrorText(message: resendTask.error)
                }
            } else {
                Section {
                    if let currentEmail { LabeledContent("Current", value: currentEmail) }
                    TextField("New email", text: $newEmail)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if hasPassword {
                        SecureField("Password", text: $password).textContentType(.password)
                    }
                } footer: {
                    VStack(alignment: .leading) {
                        Text("We'll email a 6-digit code to the new address. Your current address will be told about the change.")
                        ErrorText(message: task.error)
                    }
                }
                Section {
                    BusyButton(title: "Send code", busy: task.busy,
                               disabled: !trimmed.contains("@") || (hasPassword && password.isEmpty)) {
                        let email = trimmed
                        task.run {
                            try await model.api.requestEmailChange(newEmail: email, password: hasPassword ? password : nil)
                            sentTo = email
                        }
                    }
                }
            }
        }
        .themedForm()
        .navigationTitle(currentEmail == nil ? "Add email" : "Change email")
    }
}
