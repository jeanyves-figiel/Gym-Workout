import APIClient
import SwiftUI

struct AccountView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppLock.self) private var lock
    @State private var name = ""
    @State private var nameTask = FormTask()
    @State private var exportURL: URL?
    @State private var exportTask = FormTask()
    @State private var confirmSignOutAll = false
    @State private var signOutAllTask = FormTask()

    var body: some View {
        Form {
            if let user = model.user {
                Section("Profile") {
                    LabeledContent("Email", value: user.email ?? "Hidden (Apple)")
                    HStack {
                        TextField("Name", text: $name)
                            .textContentType(.name)
                            .onSubmit(saveName)
                        if nameTask.busy { ProgressView() }
                    }
                    ErrorText(message: nameTask.error)
                    if user.appleLinked { Label("Sign in with Apple linked", systemImage: "apple.logo") }
                }
                Section("Security") {
                    NavigationLink(user.hasPassword ? "Change password" : "Set a password") {
                        ChangePasswordView(hasPassword: user.hasPassword)
                    }
                    NavigationLink("Signed-in devices") { DevicesView() }
                    Toggle("Lock with \(lock.biometryName)", isOn: Binding(
                        get: { lock.enabled },
                        set: { on in Task { await lock.setEnabled(on) } }))
                }
            } else {
                Section { ProgressView().task { await model.refreshUser() } }
            }

            Section {
                Button("Export my data") { export() }
                    .disabled(exportTask.busy)
                if let exportURL {
                    ShareLink(item: exportURL) { Label("Share export", systemImage: "square.and.arrow.up") }
                }
                ErrorText(message: exportTask.error)
            } header: {
                Text("Your data")
            } footer: {
                Text("JSON with your account, training profile and all logged weights.")
            }

            Section {
                Button("Sign out") { Task { await model.signOut() } }
                Button("Sign out of all devices") { confirmSignOutAll = true }
                ErrorText(message: signOutAllTask.error)
            }

            Section {
                NavigationLink {
                    DeleteAccountView(hasPassword: model.user?.hasPassword ?? false)
                } label: {
                    Text("Delete account").foregroundStyle(.red)
                }
            } footer: {
                Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")")
            }
        }
        .navigationTitle("Account")
        .onAppear { name = model.user?.name ?? "" }
        .onChange(of: model.user?.name) { _, new in name = new ?? "" }
        .confirmationDialog("Sign out everywhere?", isPresented: $confirmSignOutAll, titleVisibility: .visible) {
            Button("Sign out all devices", role: .destructive) {
                signOutAllTask.run { try await model.signOutEverywhere() }
            }
        } message: {
            Text("Every device, including this one, will need to sign in again.")
        }
    }

    private func saveName() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        nameTask.run { model.user = try await model.api.updateName(trimmed.isEmpty ? nil : trimmed) }
    }

    private func export() {
        exportTask.run {
            let data = try await model.api.exportData()
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("gym-workout-export.json")
            try data.write(to: url, options: .atomic)
            exportURL = url
        }
    }
}

struct ChangePasswordView: View {
    let hasPassword: Bool
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var current = ""
    @State private var new = ""
    @State private var task = FormTask()

    var body: some View {
        Form {
            Section {
                if hasPassword {
                    SecureField("Current password", text: $current).textContentType(.password)
                }
                SecureField("New password", text: $new).textContentType(.newPassword)
            } footer: {
                VStack(alignment: .leading) {
                    Text("Other devices will be signed out.")
                    if let p = PasswordRules.problem(new) { Text(p).foregroundStyle(.red) }
                    ErrorText(message: task.error)
                }
            }
            Section {
                BusyButton(title: "Save", busy: task.busy,
                           disabled: new.isEmpty || PasswordRules.problem(new) != nil || (hasPassword && current.isEmpty)) {
                    task.run {
                        try await model.api.changePassword(current: hasPassword ? current : nil, new: new)
                        await model.refreshUser()
                        dismiss()
                    }
                }
            }
        }
        .navigationTitle(hasPassword ? "Change password" : "Set password")
    }
}

struct DevicesView: View {
    @Environment(AppModel.self) private var model
    @State private var sessions: [ActiveSession] = []
    @State private var error: String?

    var body: some View {
        List {
            ForEach(sessions, id: \.createdAt) { s in
                VStack(alignment: .leading) {
                    Text(s.device ?? "Unknown device").bold()
                    Text("Signed in " + String(s.createdAt.prefix(10))).font(.caption).foregroundStyle(.secondary)
                }
            }
            ErrorText(message: error)
        }
        .navigationTitle("Devices")
        .task {
            do { sessions = try await model.api.sessions() } catch { self.error = error.localizedDescription }
        }
    }
}

struct DeleteAccountView: View {
    let hasPassword: Bool
    @Environment(AppModel.self) private var model
    @State private var password = ""
    @State private var confirmText = ""
    @State private var task = FormTask()

    var body: some View {
        Form {
            Section {
                Text("This permanently deletes your account, training profile and all logged weights from the server and this device. It cannot be undone.")
                Text("Tip: export your data first.").foregroundStyle(.secondary)
            }
            Section {
                if hasPassword {
                    SecureField("Password", text: $password).textContentType(.password)
                }
                TextField("Type DELETE to confirm", text: $confirmText)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
            } footer: {
                ErrorText(message: task.error)
            }
            Section {
                BusyButton(title: "Delete my account", busy: task.busy,
                           disabled: confirmText != "DELETE" || (hasPassword && password.isEmpty)) {
                    task.run { try await model.deleteAccount(password: hasPassword ? password : nil) }
                }
                .foregroundStyle(.red)
            }
        }
        .navigationTitle("Delete account")
    }
}
