# NovaStorm IPTV — iOS / iPadOS

Native SwiftUI + AVPlayer client for the RV IPTV Gateway. Built, signed and uploaded to
**TestFlight by GitHub Actions** (no Mac needed): every push to `main` becomes a TestFlight build,
and TestFlight on your iPhone/iPad offers it as an update.

MKV titles (74% of the catalog) play through the gateway's on-demand HLS remux (`/hlsvod/...`);
MP4 plays directly. Live TV is the gateway's HLS, which Apple's player handles natively.

## One-time setup (Apple developer web portal — no Mac)

1. **App ID** — developer.apple.com → Certificates, Identifiers & Profiles → Identifiers → **+** →
   App IDs → App → Bundle ID *Explicit* `com.novastorm.iptv`, description "NovaStorm IPTV" → Register.
2. **Distribution certificate** — Certificates → **+** → *Apple Distribution* → upload
   `signing/apple_distribution.csr` (generated in this repo) → download the `.cer` and hand it back;
   it gets combined with the local private key into the `.p12` the CI signs with.
3. **App Store Connect API key** — appstoreconnect.apple.com → Users and Access → Integrations →
   App Store Connect API → Team Keys → **+** → name "GitHub Actions", role *App Manager* →
   note the **Key ID** and **Issuer ID**, download `AuthKey_<KEYID>.p8` (one-time download).
4. **App record** — App Store Connect → Apps → **+** New App → iOS, name "NovaStorm IPTV",
   bundle ID `com.novastorm.iptv`, SKU `novastorm-iptv` → Create.
5. **Testers** — that app → TestFlight → Internal Testing → create a group, add yourself.
   Install **TestFlight** from the App Store on the iPhone/iPad.
6. **Team ID** — developer.apple.com → Membership details → 10-character Team ID.

## GitHub repository secrets (Settings → Secrets and variables → Actions)

| Secret | Value |
|---|---|
| `APPLE_TEAM_ID` | the 10-character Team ID |
| `ASC_KEY_ID` | API key ID |
| `ASC_ISSUER_ID` | API issuer ID |
| `ASC_KEY_P8` | full contents of `AuthKey_<KEYID>.p8` |
| `DIST_CERT_P12_BASE64` | base64 of `signing/apple_distribution.p12` (produced after step 2) |
| `DIST_CERT_PASSWORD` | the password chosen when the `.p12` was made |

Paste these yourself — the pipeline is designed so nobody else needs to hold them.

## Release

Push to `main`. About ten minutes later TestFlight notifies the devices. Build numbers come from
the GitHub run number, so every push is a distinct build.

## Layout

- `NovaStormIPTV/Data` — models, gateway client, live/VOD folder logic, catalog cache, history.
  Pure Foundation; type-checks with the Windows Swift toolchain.
- `NovaStormIPTV/UI` — SwiftUI screens (compile on the macOS runner only).
- `project.yml` — XcodeGen spec; the `.xcodeproj` is generated on the runner.
