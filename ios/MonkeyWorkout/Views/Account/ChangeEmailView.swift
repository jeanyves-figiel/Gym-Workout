import APIClient
import SwiftUI

/// Change (or add) the account email: code sent to the new address, old address notified (#12).
struct ChangeEmailView: View {
    let currentEmail: String?
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var newEmail = ""
    @State private var gate = ReauthGate()
    @State private var code = ""
    @State private var sentTo: String?
    @State private var task = FormTask()
    @State private var resendTask = FormTask()
    @State private var closeGuard = CloseGuard()

    /// The new address and sent code, kept for Undo (#285).
    struct Draft: Equatable {
        var newEmail: String
        var sentTo: String?
        var code: String
    }

    /// `restoring`: brought back by Undo (#285), so the code that was sent can still be typed.
    init(currentEmail: String?, restoring: Draft? = nil) {
        self.currentEmail = currentEmail
        _newEmail = State(initialValue: restoring?.newEmail ?? "")
        _sentTo = State(initialValue: restoring?.sentTo)
        _code = State(initialValue: restoring?.code ?? "")
    }

    /// Undo bar once a code was sent (#285).
    private var undoOffer: UndoOffer? {
        guard let sentTo else { return nil }
        let kept = Draft(newEmail: newEmail, sentTo: sentTo, code: code)
        let current = self.currentEmail
        return UndoOffer(title: "Email change closed", detail: undoDetail("Code sent to \(sentTo)"), symbol: "envelope.badge.fill",
                         colors: [Color(red: 0, green: 0.79, blue: 0.65), Color(red: 0.18, green: 0.77, blue: 1)]) {
            AnyView(UndoReopenedPush { ChangeEmailView(currentEmail: current, restoring: kept) })
        }
    }

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
                            closeGuard.done()
                            dismiss()
                        }
                    }
                    HStack(spacing: 10) {
                        AccountPillButton(title: resendTask.busy ? "Sending…" : "Resend code") {
                            resendTask.run { try await gate.run(model.api) { try await model.api.requestEmailChange(newEmail: sentTo) } }
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
                    AccountNote(text: "We'll ask you to confirm it's you, then email a 6-digit code to the new address. Your current address will be told about the change.")
                    ErrorText(message: task.error)
                    LimeActionButton(title: "Send code", busy: task.busy,
                                     disabled: !trimmed.contains("@")) {
                        let email = trimmed
                        task.run {
                            // Confirm it's you first (#257).
                            try await gate.run(model.api) { try await model.api.requestEmailChange(newEmail: email) }
                            sentTo = email
                        }
                    }
                }
            }
            .padding(16)
        }
        .readableWidth()
        .themedForm()
        .navigationTitle(currentEmail == nil ? "Add email" : "Change email")
        .toolbarTitleDisplayMode(.inline)
        .reauthSheet(gate)
        .undoableClose(closeGuard, offer: undoOffer)
    }
}
