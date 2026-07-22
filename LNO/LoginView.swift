import SwiftUI

struct LoginView: View {
    @EnvironmentObject var auth: AuthStore
    @State private var email = ""
    @State private var password = ""
    @State private var showEmail = false
    @FocusState private var focus: Field?
    enum Field { case email, password }

    var body: some View {
        ZStack {
            AuthBackground()
            ScrollView {
                VStack(spacing: 22) {
                    Spacer(minLength: 40)
                    LNOLogo().frame(width: 220, height: 220 * (190.6 / 824))
                    Text("Control Center")
                        .font(.subheadline)
                        .foregroundStyle(Color.white.opacity(0.65))

                    VStack(alignment: .leading, spacing: 14) {
                        Text("Sign in").font(.title3).fontWeight(.semibold).foregroundStyle(Theme.navy)

                        // Google is the default sign-in (same as the web dashboard).
                        googleButton

                        if let err = auth.errorMessage {
                            Text(err).font(.footnote).foregroundStyle(Theme.down)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .multilineTextAlignment(.center)
                        }

                        // Break-glass: email/password for external shareholders & the admin.
                        if showEmail {
                            emailForm
                        } else {
                            Button {
                                withAnimation { showEmail = true }
                            } label: {
                                Text("Sign in with email instead")
                                    .font(.footnote).fontWeight(.medium)
                                    .foregroundStyle(Theme.mutedText)
                                    .underline()
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 2)
                        }
                    }
                    .padding(20)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .shadow(color: .black.opacity(0.25), radius: 20, y: 8)

                    Text("Accounts are created on the LNO dashboard.\nThis app is view-only.")
                        .font(.caption).foregroundStyle(Color.white.opacity(0.5))
                        .multilineTextAlignment(.center)

                    #if DEBUG
                    Button {
                        auth.enterDemoMode()
                    } label: {
                        Text("Preview demo (DEBUG)")
                            .font(.caption2).fontWeight(.semibold)
                            .foregroundStyle(Theme.gold)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(Color.white.opacity(0.1))
                            .clipShape(Capsule())
                    }
                    .padding(.top, 4)
                    #endif

                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 22)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    // MARK: - Google (default)

    /// Mirrors the web dashboard's official Google Identity Services button
    /// (theme "outline", shape "pill", text "signin_with").
    private var googleButton: some View {
        Button {
            focus = nil
            Task { await auth.signInWithGoogle() }
        } label: {
            HStack(spacing: 10) {
                if auth.busy && !showEmail { ProgressView().tint(Color(hex: 0x3C4043)) }
                else { GoogleGMark(size: 18) }
                Text("Sign in with Google")
                    .font(.system(size: 15, weight: .medium))
            }
            .frame(maxWidth: .infinity).padding(.vertical, 13)
        }
        .foregroundStyle(Color(hex: 0x3C4043))
        .background(Color.white)
        .overlay(Capsule().stroke(Color(hex: 0xDADCE0), lineWidth: 1))
        .clipShape(Capsule())
        .disabled(auth.busy)
        .opacity(auth.busy ? 0.7 : 1)
    }

    // MARK: - Email / password (secondary)

    private var emailForm: some View {
        VStack(spacing: 12) {
            HStack { line; Text("shareholders & admin").font(.caption2).foregroundStyle(Theme.faintText); line }

            field(icon: "envelope", placeholder: "Email", text: $email)
                .keyboardType(.emailAddress)
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focus, equals: .email)
                .submitLabel(.next)
                .onSubmit { focus = .password }

            secureField(icon: "lock", placeholder: "Password", text: $password)
                .textContentType(.password)
                .focused($focus, equals: .password)
                .submitLabel(.go)
                .onSubmit(submit)

            Button(action: submit) {
                HStack {
                    if auth.busy { ProgressView().tint(.white) }
                    Text("Sign in").fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 13)
            }
            .background(Theme.navy).foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .disabled(auth.busy || email.isEmpty || password.isEmpty)
            .opacity((auth.busy || email.isEmpty || password.isEmpty) ? 0.6 : 1)
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var line: some View { Rectangle().fill(Theme.stroke).frame(height: 1) }

    private func submit() {
        guard !email.isEmpty, !password.isEmpty else { return }
        focus = nil
        Task { await auth.signIn(email: email, password: password) }
    }

    private func field(icon: String, placeholder: String, text: Binding<String>) -> some View {
        HStack {
            Image(systemName: icon).foregroundStyle(Theme.faintText).frame(width: 20)
            TextField("", text: text, prompt: Text(placeholder).foregroundColor(Theme.faintText))
                .foregroundStyle(Theme.navy)
        }
        .padding(.horizontal, 14).padding(.vertical, 13)
        .background(Color.white)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: 0xCBD5E1), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
    private func secureField(icon: String, placeholder: String, text: Binding<String>) -> some View {
        HStack {
            Image(systemName: icon).foregroundStyle(Theme.faintText).frame(width: 20)
            SecureField("", text: text, prompt: Text(placeholder).foregroundColor(Theme.faintText))
                .foregroundStyle(Theme.navy)
        }
        .padding(.horizontal, 14).padding(.vertical, 13)
        .background(Color.white)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(hex: 0xCBD5E1), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
