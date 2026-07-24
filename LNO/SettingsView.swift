import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject var loc: LanguageStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(spacing: 16) {
                        profileCard
                        languageCard
                        securityCard
                        infoCard
                        Button(role: .destructive) {
                            auth.signOut(); dismiss()
                        } label: {
                            Text("Sign out").frame(maxWidth: .infinity).padding(.vertical, 12)
                        }
                        .background(Theme.down.opacity(0.1))
                        .foregroundStyle(Theme.down)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.white, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.light)
        .tint(Theme.gold)
    }

    @ViewBuilder private var profileCard: some View {
        if let u = auth.user {
            Card {
                HStack(spacing: 14) {
                    AvatarView(user: u, diameter: 52)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(u.displayName).font(.headline).foregroundStyle(Theme.navy)
                        Text(u.email).font(.caption).foregroundStyle(Theme.mutedText)
                        Text(u.role.capitalized).font(.caption2).fontWeight(.semibold)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Theme.gold.opacity(0.15)).clipShape(Capsule())
                            .foregroundStyle(Color(hex: 0x8A6C2E))
                    }
                    Spacer()
                }
            }
        }
    }

    /// 4-way picker mirroring the web dashboard's sidebar `LangSwitcher` — picking
    /// one here applies instantly and (once signed in) becomes the shared default
    /// synced to the account, same as picking one on the web.
    private var languageCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("Language").font(.subheadline).fontWeight(.semibold).foregroundStyle(Theme.navy)
                Picker("Language", selection: Binding(
                    get: { loc.lang },
                    set: { loc.setLang($0, auth: auth) }
                )) {
                    ForEach(Lang.allCases) { l in
                        Text(l.displayCode).tag(l)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    @State private var faceIDBusy = false

    @ViewBuilder private var securityCard: some View {
        if BiometricAuth.isAvailable {
            Card {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(isOn: Binding(
                        get: { auth.faceIDEnabled },
                        set: { toggleFaceID($0) }
                    )) {
                        Label("Require \(BiometricAuth.kindName)", systemImage: "faceid")
                            .foregroundStyle(Theme.navy)
                    }
                    .tint(Theme.gold)
                    .disabled(faceIDBusy)
                    Text("Lock the app between launches; unlock with \(BiometricAuth.kindName) instead of signing in again.")
                        .font(.caption).foregroundStyle(Theme.mutedText)
                }
            }
        }
    }

    /// Turning this on should take effect immediately, not just get remembered
    /// for the next cold launch — so confirm biometrics right here, on toggle,
    /// and only actually enable the setting once that confirmation succeeds.
    /// Turning off needs no confirmation.
    private func toggleFaceID(_ on: Bool) {
        guard on else { auth.setFaceIDEnabled(false); return }
        faceIDBusy = true
        Task {
            let ok = await BiometricAuth.authenticate(reason: "Enable \(BiometricAuth.kindName) to lock LNO Control Center")
            if ok { auth.setFaceIDEnabled(true) }
            faceIDBusy = false
        }
    }

    private var infoCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 8) {
                Text("LNO Control Center").font(.subheadline).fontWeight(.semibold).foregroundStyle(Theme.navy)
                Text("View-only companion to the LNO dashboard. Accounts are managed at cc.lno.company.")
                    .font(.caption).foregroundStyle(Theme.mutedText)
                if !Config.pushConfigured {
                    Label("Push alerts not yet enabled", systemImage: "bell.slash")
                        .font(.caption2).foregroundStyle(Theme.faintText)
                }
            }
        }
    }

}
