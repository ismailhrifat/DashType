import SwiftUI

struct CloudSyncAuthSheetView: View {
    @ObservedObject var cloudSyncManager: CloudSyncManager

    @State private var authMode: CloudSyncManager.AuthFlowMode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var localErrorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Cloud Sync")
                .font(.system(size: 24, weight: .bold))

            Text("Sign in or create an account to sync your snippets with Cloud.")
                .foregroundStyle(.secondary)

            Picker("Auth Mode", selection: $authMode) {
                ForEach(CloudSyncManager.AuthFlowMode.allCases) { mode in
                    Text(mode.rawValue)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 12) {
                TextField("Email", text: $email)
                    .textFieldStyle(.roundedBorder)
                    .textContentType(.emailAddress)

                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)

                if authMode == .signUp {
                    SecureField("Confirm Password", text: $confirmPassword)
                        .textFieldStyle(.roundedBorder)
                }
            }

            if let authErrorMessage = localErrorMessage ?? cloudSyncManager.authErrorMessage {
                Text(authErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Cancel") {
                    cloudSyncManager.dismissAuthSheet()
                }

                Spacer()

                Button(authMode.actionTitle) {
                    DispatchQueue.main.async {
                        submit()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSubmit || cloudSyncManager.isAuthenticating)
            }
        }
        .padding(24)
        .frame(width: 420)
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    Color.accentColor.opacity(0.05),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .onAppear {
            authMode = cloudSyncManager.authFlowMode
        }
        .onChange(of: authMode) { _, _ in
            localErrorMessage = nil
            confirmPassword = ""
            DispatchQueue.main.async {
                cloudSyncManager.clearAuthError()
            }
        }
    }

    private var canSubmit: Bool {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty, !password.isEmpty else {
            return false
        }

        if authMode == .signUp {
            return password == confirmPassword
        }

        return true
    }

    private func submit() {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        localErrorMessage = nil

        if authMode == .signUp, password != confirmPassword {
            localErrorMessage = "Passwords do not match."
            return
        }

        switch authMode {
        case .signIn:
            cloudSyncManager.signIn(email: trimmedEmail, password: password)
        case .signUp:
            cloudSyncManager.signUp(email: trimmedEmail, password: password)
        }
    }
}
