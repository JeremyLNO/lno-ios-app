import SwiftUI

struct LoginView: View {
    @EnvironmentObject var auth: AuthStore
    @State private var email = ""
    @State private var code = ""
    @State private var otpStep: OtpStep = .hidden
    @State private var now = Date()
    @FocusState private var focus: Field?
    enum Field { case email, code }
    enum OtpStep { case hidden, email, code }

    private static let resendCooldown: TimeInterval = 60

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

                        // Google is the only sign-in for @lno.company accounts (no password
                        // login anywhere in this app — see requestOtp's GOOGLE_ONLY gate).
                        googleButton

                        if let err = auth.errorMessage {
                            Text(err).font(.footnote).foregroundStyle(Theme.down)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .multilineTextAlignment(.center)
                        }

                        // Shareholders (external, non-@lno.company emails) sign in with an
                        // emailed 6-digit code instead — no password anywhere in this flow.
                        switch otpStep {
                        case .hidden:
                            Button {
                                withAnimation { otpStep = .email }
                            } label: {
                                Text("Sign in with an emailed code")
                                    .font(.footnote).fontWeight(.medium)
                                    .foregroundStyle(Theme.mutedText)
                                    .underline()
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 2)
                        case .email:
                            otpEmailForm
                        case .code:
                            otpCodeForm
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
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { t in
            if otpStep == .code { now = t }
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
                if auth.busy && otpStep == .hidden { ProgressView().tint(Color(hex: 0x3C4043)) }
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

    // MARK: - Emailed code (shareholders)

    private var isLnoEmail: Bool { email.lowercased().hasSuffix("@lno.company") }

    private var otpEmailForm: some View {
        VStack(spacing: 12) {
            HStack { line; Text("shareholders").font(.caption2).foregroundStyle(Theme.faintText); line }

            field(icon: "envelope", placeholder: "Email", text: $email)
                .keyboardType(.emailAddress)
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focus, equals: .email)
                .submitLabel(.go)
                .onSubmit(sendCode)

            if isLnoEmail {
                Text("@lno.company accounts sign in with Google above.")
                    .font(.caption2).foregroundStyle(Theme.mutedText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button(action: sendCode) {
                HStack {
                    if auth.busy { ProgressView().tint(.white) }
                    Text("Send code").fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 13)
            }
            .background(Theme.navy).foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .disabled(auth.busy || email.isEmpty || isLnoEmail)
            .opacity((auth.busy || email.isEmpty || isLnoEmail) ? 0.6 : 1)

            Button {
                withAnimation { otpStep = .hidden; auth.errorMessage = nil }
            } label: {
                Text("Cancel").font(.footnote).foregroundStyle(Theme.mutedText)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var resendRemaining: Int {
        guard let requestedAt = auth.otpRequestedAt else { return 0 }
        return max(0, Int(Self.resendCooldown - now.timeIntervalSince(requestedAt)))
    }

    private var otpCodeForm: some View {
        VStack(spacing: 12) {
            HStack { line; Text("code sent to \(email)").font(.caption2).foregroundStyle(Theme.faintText); line }

            field(icon: "number", placeholder: "6-digit code", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($focus, equals: .code)
                .submitLabel(.go)
                .onSubmit(verifyCode)
                .onChange(of: code) { _, v in
                    code = String(v.filter(\.isNumber).prefix(6))
                    if code.count == 6 { verifyCode() }
                }

            Button(action: verifyCode) {
                HStack {
                    if auth.busy { ProgressView().tint(.white) }
                    Text("Verify").fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 13)
            }
            .background(Theme.navy).foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .disabled(auth.busy || code.count != 6)
            .opacity((auth.busy || code.count != 6) ? 0.6 : 1)

            HStack {
                Button {
                    withAnimation { otpStep = .email; code = ""; auth.errorMessage = nil }
                } label: {
                    Text("Change email").font(.footnote).foregroundStyle(Theme.mutedText)
                }
                Spacer()
                Button(action: sendCode) {
                    Text(resendRemaining > 0 ? "Resend (\(resendRemaining)s)" : "Resend code")
                        .font(.footnote).foregroundStyle(resendRemaining > 0 ? Theme.faintText : Theme.mutedText)
                }
                .disabled(auth.busy || resendRemaining > 0)
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var line: some View { Rectangle().fill(Theme.stroke).frame(height: 1) }

    private func sendCode() {
        guard !email.isEmpty, !isLnoEmail else { return }
        focus = nil
        Task {
            if await auth.requestOtp(email: email) {
                withAnimation { otpStep = .code }
                code = ""
                focus = .code
            }
        }
    }

    private func verifyCode() {
        guard code.count == 6 else { return }
        focus = nil
        Task { await auth.verifyOtp(email: email, code: code) }
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
}
