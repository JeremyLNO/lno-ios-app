import SwiftUI

/// Shown when a session is stored but Face ID/Touch ID hasn't unlocked it yet.
struct LockScreenView: View {
    @EnvironmentObject var auth: AuthStore
    @State private var attempted = false

    var body: some View {
        ZStack {
            AuthBackground()
            VStack(spacing: 22) {
                Spacer()
                LNOLogo().frame(width: 180, height: 180 * (190.6 / 824))
                Image(systemName: "faceid")
                    .font(.system(size: 44))
                    .foregroundStyle(Theme.gold)
                    .padding(.top, 8)
                Text("LNO Control Center is locked")
                    .font(.headline).foregroundStyle(.white)
                if let err = auth.errorMessage {
                    Text(err).font(.footnote).foregroundStyle(Theme.down)
                        .multilineTextAlignment(.center).padding(.horizontal, 32)
                }
                Button {
                    Task { await auth.unlockWithFaceID() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "faceid")
                        Text("Unlock with \(BiometricAuth.kindName)")
                    }
                    .fontWeight(.semibold)
                    .frame(maxWidth: 260).padding(.vertical, 13)
                }
                .background(Theme.gold).foregroundStyle(Theme.navy)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                Button("Sign out instead") { auth.signOut() }
                    .font(.footnote).foregroundStyle(Color.white.opacity(0.6))
                    .padding(.top, 4)
                Spacer()
                Spacer()
            }
            .frame(maxWidth: .infinity)
        }
        .task {
            guard !attempted else { return }
            attempted = true
            await auth.unlockWithFaceID()
        }
    }
}
