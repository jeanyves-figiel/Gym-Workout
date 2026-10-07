import SwiftUI

struct VerifyEmailView: View {
    let email: String
    @Environment(AppModel.self) private var model
    @State private var code = ""
    @State private var task = FormTask()
    @State private var resent = false

    var body: some View {
        Form {
            Section {
                TextField("6-digit code", text: $code)
                    .textContentType(.oneTimeCode)
                    .keyboardType(.numberPad)
                    .font(.title2.monospacedDigit())
                    .onChange(of: code) { _, new in
                        code = String(new.filter(\.isNumber).prefix(6))
                        if code.count == 6 { submit() }
                    }
            } header: {
                Text("Check your email")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("We sent a code to \(email). It expires in 15 minutes.")
                    ErrorText(message: task.error)
                }
            }
            Section {
                BusyButton(title: "Verify", busy: task.busy, disabled: code.count != 6, action: submit)
                Button(resent ? "Code sent" : "Resend code") {
                    Task {
                        try? await model.api.resendVerification(email: email)
                        resent = true
                    }
                }
                .disabled(resent)
            }
        }
        .navigationTitle("Verify email")
    }

    private func submit() {
        task.run {
            let user = try await model.api.verifyEmail(email: email, code: code)
            await model.didAuthenticate(user)
        }
    }
}
