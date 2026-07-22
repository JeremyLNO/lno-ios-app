# LNO Control Center — iOS

Private, **read-only** iOS companion to the LNO Control Center dashboard
([cc.lno.company](https://cc.lno.company)). Same backend, same database — the app
only *views* data; all accounts are created on the web dashboard.

Native SwiftUI, single target, no external SDKs in V1.

## Run

```bash
./build-run.sh                    # build + install + launch on the Simulator
LNO_DEVICE="iPhone 16" ./build-run.sh
```

`build-run.sh` regenerates the Xcode project from the sources on disk
(`gen_pbxproj.py`), so **just add/remove `.swift` files in `LNO/` and rebuild** —
no manual `.pbxproj` editing.

- Bundle id: `company.lno.controlcenter`
- Min iOS: 17.0

## Architecture

- **`APIClient.swift`** — async client for `https://cc.lno.company/api`, JWT bearer
  auth. Reads: `bots` (+`live`), `funds`, `snapshots`, `alerts`. Plus public
  Binance USDⓈ-M tickers for the Prices tab (mirrors the web app).
- **`AuthStore.swift`** — login state. Email/password + Google (OAuth 2.0 + PKCE via
  `ASWebAuthenticationSession`). JWT stored in the Keychain.
- **`PortfolioStore.swift`** — shared data + KPIs derived client-side exactly like
  `api/_lib/portfolio.js` (equity, day P&L, open P&L, exposure, funds grouping).
- Tabs: **Overview**, **Positions**, **Prices**, **Alerts** + an Account sheet.

## Phase 2 (needs credentials / accounts)

Config-gated in `Config.swift` — the app runs fine with these empty:

1. **Google sign-in** — set `googleIOSClientID` to an iOS OAuth client from the LNO
   Google Cloud project. The backend `api/_lib/google.js` must also accept that
   client ID as a valid token **audience** (currently only the web client ID is
   accepted).
2. **Push (OneSignal)** — set `oneSignalAppID`, add the OneSignal SDK, and add a
   hook in the backend `api/_lib/notify.js` to push when an alert fires. Real-device
   push needs an Apple Developer account.
