import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var auth: AuthStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                AppBackground()
                ScrollView {
                    VStack(spacing: 16) {
                        profileCard
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
                    ZStack {
                        Circle().fill(Theme.navy).frame(width: 52, height: 52)
                        Text(initials(u)).font(.headline).foregroundStyle(.white)
                    }
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

    @ViewBuilder private var securityCard: some View {
        if BiometricAuth.isAvailable {
            Card {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle(isOn: Binding(
                        get: { auth.faceIDEnabled },
                        set: { auth.setFaceIDEnabled($0) }
                    )) {
                        Label("Require \(BiometricAuth.kindName)", systemImage: "faceid")
                            .foregroundStyle(Theme.navy)
                    }
                    .tint(Theme.gold)
                    Text("Lock the app between launches; unlock with \(BiometricAuth.kindName) instead of signing in again.")
                        .font(.caption).foregroundStyle(Theme.mutedText)
                }
            }
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

    private func initials(_ u: User) -> String {
        let f = u.firstName.first.map(String.init) ?? ""
        let l = u.lastName.first.map(String.init) ?? ""
        let s = (f + l).uppercased()
        return s.isEmpty ? String(u.email.prefix(1)).uppercased() : s
    }
}
