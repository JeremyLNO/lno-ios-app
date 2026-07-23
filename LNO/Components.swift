import SwiftUI
import Charts

/// A white card container matching the dashboard's `Card` (bg-white, rounded-xl,
/// slate-200/80 border, shadow-sm).
struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.cardBG)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.stroke, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
    }
}

/// A single KPI tile matching the web's `KpiCard`: label + icon chip top row,
/// big navy value, optional trend badge below.
struct KPITile: View {
    let label: String
    let value: String
    var icon: String? = nil
    var accent: Color? = nil
    var sub: String? = nil
    var subColor: Color = Theme.mutedText

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(label.uppercased())
                        .font(.caption2).fontWeight(.medium)
                        .foregroundStyle(Theme.mutedText)
                    Spacer()
                    if let icon {
                        ZStack {
                            if let accent {
                                RoundedRectangle(cornerRadius: 8).fill(accent.opacity(0.1))
                                    .frame(width: 28, height: 28)
                                Image(systemName: icon).font(.system(size: 13)).foregroundStyle(accent)
                            } else {
                                Image(systemName: icon).font(.system(size: 13)).foregroundStyle(Theme.faintText)
                            }
                        }
                    }
                }
                Text(value)
                    .font(.system(.title2, design: .rounded)).fontWeight(.bold)
                    .foregroundStyle(Theme.navy)
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .padding(.top, 6)
                if let sub {
                    Text(sub).font(.caption).fontWeight(.medium).foregroundStyle(subColor)
                        .padding(.top, 2)
                }
            }
        }
    }
}

/// Plain colored text for LONG/SHORT — matches the web's `SideTag` (no pill bg).
struct SideBadge: View {
    let isLong: Bool
    var body: some View {
        Text(isLong ? "LONG" : "SHORT")
            .font(.caption2).fontWeight(.semibold)
            .foregroundStyle(isLong ? Theme.up : Theme.down)
    }
}

/// Coloured dot for a fund (used standalone, e.g. next to a section title).
struct FundDot: View {
    let color: String
    var size: CGFloat = 10
    var body: some View {
        Circle().fill(Color(hexString: color) ?? Theme.gold).frame(width: size, height: size)
    }
}

/// Soft-tint pill for a fund name — matches the web's `Badge`/`FundTag`
/// (background = color at 10% opacity, text = the color itself, small leading dot).
struct FundBadge: View {
    let name: String
    let color: String
    var body: some View {
        let c = Color(hexString: color) ?? Theme.gold
        HStack(spacing: 5) {
            Circle().fill(c).frame(width: 6, height: 6)
            Text(name).font(.caption).fontWeight(.medium)
        }
        .foregroundStyle(c)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(c.opacity(0.1))
        .clipShape(Capsule())
    }
}

/// Equity area chart from recorded snapshots — light-mode axis/gridlines.
struct EquityChart: View {
    let snapshots: [Snapshot]
    var body: some View {
        let up = (snapshots.last?.equity ?? 0) >= (snapshots.first?.equity ?? 0)
        let tint = up ? Theme.up : Theme.down
        Chart(snapshots) { s in
            AreaMark(
                x: .value("Day", s.day),
                y: .value("Equity", s.equity)
            )
            .interpolationMethod(.monotone)
            .foregroundStyle(LinearGradient(colors: [tint.opacity(0.22), tint.opacity(0.02)],
                                            startPoint: .top, endPoint: .bottom))
            LineMark(x: .value("Day", s.day), y: .value("Equity", s.equity))
                .interpolationMethod(.monotone)
                .foregroundStyle(tint)
                .lineStyle(StrokeStyle(lineWidth: 2))
        }
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .trailing) { v in
                AxisGridLine().foregroundStyle(Color(hex: 0xEEF0F3))
                AxisValueLabel {
                    if let d = v.as(Double.self) {
                        Text(Fmt.usd(d)).font(.caption2).foregroundStyle(Theme.faintText)
                    }
                }
            }
        }
        .frame(height: 180)
    }
}

/// Full-screen states shared by data tabs.
struct LoadingView: View {
    var body: some View {
        ProgressView().tint(Theme.gold)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ErrorView: View {
    let message: String
    let retry: () -> Void
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(Theme.warn)
            Text(message).multilineTextAlignment(.center).foregroundStyle(Theme.mutedText)
            Button("Retry", action: retry).buttonStyle(.borderedProminent).tint(Theme.navy)
        }
        .padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.largeTitle).foregroundStyle(Theme.faintText)
            Text(title).font(.headline).foregroundStyle(Theme.navy)
            if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(Theme.mutedText) }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}

/// Cream page background used behind every signed-in screen (matches web's `bg-bg`
/// #F8F7F4). The navy gradient is reserved for the pre-auth screens (Login/Lock),
/// which mirror the web login page's navy full-bleed background.
struct AppBackground: View {
    var body: some View {
        Theme.pageBG.ignoresSafeArea()
    }
}

/// Navy full-bleed background for Login/Lock screens, matching the web's
/// `bg-navy` login page (the signed-in app itself is light, this is not).
struct AuthBackground: View {
    var body: some View {
        LinearGradient(colors: [Theme.navy, Color(hex: 0x081627)],
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }
}

extension View {
    /// The one top bar every tab uses: LNO mark top-left, page title inline,
    /// profile avatar top-right — same navigationBarTitleDisplayMode (.inline)
    /// everywhere. Tabs used to pick their own (Overview was .inline, the other
    /// three were .large), which made the header a different height per tab.
    func lnoTopBar(_ title: String, auth: AuthStore, showSettings: Binding<Bool>) -> some View {
        self
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.white, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    LNOLogo(color: Theme.navy, showWordmark: false).frame(width: 30, height: 30)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings.wrappedValue = true } label: {
                        if let user = auth.user {
                            AvatarView(user: user, diameter: 28)
                        } else {
                            Image(systemName: "person.crop.circle").foregroundStyle(Theme.navy)
                        }
                    }
                }
            }
    }
}

/// The user's profile photo, matching the web dashboard exactly: same source
/// (`User.avatar`, a `data:image/…;base64,…` string written by the web's upload
/// control — see ProfilePage.tsx), same fallback (initials on a navy circle) when
/// no photo has been set. Decoded client-side since URLSession/AsyncImage don't
/// fetch `data:` URLs.
struct AvatarView: View {
    let user: User
    var diameter: CGFloat = 52

    var body: some View {
        Group {
            if let uiImage = Self.decode(user.avatar) {
                Image(uiImage: uiImage).resizable().scaledToFill()
            } else {
                Circle().fill(Theme.navy).overlay(
                    Text(initials).font(.system(size: diameter * 0.38, weight: .semibold))
                        .foregroundStyle(.white)
                )
            }
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
    }

    private var initials: String {
        let f = user.firstName.first.map(String.init) ?? ""
        let l = user.lastName.first.map(String.init) ?? ""
        let combined = (f + l).uppercased()
        return combined.isEmpty ? String(user.email.prefix(1)).uppercased() : combined
    }

    private static func decode(_ dataURL: String?) -> UIImage? {
        guard let dataURL, let comma = dataURL.firstIndex(of: ",") else { return nil }
        let base64 = dataURL[dataURL.index(after: comma)...]
        guard let data = Data(base64Encoded: String(base64)) else { return nil }
        return UIImage(data: data)
    }
}
