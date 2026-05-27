# GlucoGlance

A personal-use iPhone + Apple Watch viewer for FreeStyle Libre continuous
glucose monitor (CGM) data, pulled from your own LibreLinkUp account.

> ⚠️ **Not a medical device. Not affiliated with Abbott Diabetes Care,
> FreeStyle Libre, or LibreView.** Glucose values shown by this app are
> informational only and must not be used for clinical decisions, insulin
> dosing, or emergency response. Always confirm readings in the official
> LibreLink app, or with a fingerstick measurement, before making any
> treatment decisions.

## What it does

- iPhone dashboard with current glucose value, trend, color-coded ranges, 24h chart, time-in-range, and 15-minute delta
- Apple Watch app + complications (circular, rectangular, inline, corner) — glance at your wrist to see your glucose
- Auto-refresh every 60 seconds while the app is open, every 5 minutes in the watch background
- Optional Apple Health (HealthKit) integration — writes glucose readings into the Health app
- Credentials stored in iOS Keychain (never plaintext UserDefaults)
- Surfaces sync failures with a clear red banner so stale readings are never silently shown as "current"
- Display unit auto-selected from your LibreLinkUp account country (mmol/L for AU/UK/EU/etc., mg/dL for US)

## Why this exists

Outside the US, FreeStyle Libre is the most common CGM sensor, and Abbott's
official apps don't have a great Apple Watch story. The DIY diabetes community
has been building viewers, dashboards, and watch tools for over a decade
(Loop, xDrip+, Nightscout, AAPS). GlucoGlance is a clean, modern SwiftUI
iteration on the same idea — built for personal use because I'm a Type 1
diabetic and I wanted a nice watch complication.

## Important disclaimer

This is a **personal-use** project. It is not on the App Store and is not
intended for commercial distribution. The code is published under MIT so
that other people in the same situation can fork it and build their own
copy.

The app communicates with Abbott's LibreLinkUp service using community
reverse-engineered endpoints. Abbott can change those endpoints at any
time and the app would break until the code is updated.

## Tech stack

- SwiftUI on iOS 17+ and watchOS 10+
- WidgetKit accessory widget families (`.accessoryCircular`, `.accessoryRectangular`, `.accessoryInline`, `.accessoryCorner`)
- HealthKit (iOS only; optional)
- Keychain Services with a shared access group between iOS app and watch app
- WatchConnectivity for iPhone ↔ Watch sync
- Swift Charts for dashboards

## How the data flows

```
FreeStyle Libre sensor
       │  NFC / BLE
       ▼
Official LibreLink iOS app
       │  uploads to Abbott cloud
       ▼
LibreView / LibreLinkUp cloud
       │  HTTPS, community-documented endpoints
       ▼
GlucoGlance (this app)
       │  Keychain-stored bearer token
       ▼
iPhone dashboard + Watch complication
```

GlucoGlance never touches the sensor directly. It signs in to your existing
LibreLinkUp account and reads the data the official LibreLinkUp caregiver app
would read.

## Building it for yourself

### Prerequisites
- macOS with Xcode 15 or later
- iPhone running iOS 17.0+
- (Optional) Apple Watch running watchOS 10.0+
- Apple ID — a free Personal Team works for personal sideloading; a paid
  Apple Developer Program account gives you 90-day TestFlight builds
- A LibreLinkUp account with an active FreeStyle Libre sensor and at least
  one shared patient (the patient can be yourself if you're using both the
  LibreLink and LibreLinkUp apps)

### Steps

1. Clone the repo:
   ```bash
   git clone https://github.com/rajashekharans/glucoglance.git
   cd glucoglance
   open LibreGlucoseWatch.xcodeproj
   ```

2. In Xcode, change the bundle identifiers from `com.rajnaidu.LibreGlucoseWatch.*`
   to your own reverse-domain prefix (e.g., `com.yourname.glucoglance.*`) across
   the three targets: iOS app, watch app, and widget extension.

3. Update the App Group identifier in entitlements files to match your prefix,
   and similarly update the Keychain access group in
   `LibreGlucoseWatch.entitlements` and `LibreGlucoseWatch Watch App.entitlements`.
   Also update the `suiteName` constants in `Shared/GlucoseStore.swift` and the
   widget's `GlucoseWidget.swift`.

4. Select your Apple ID team in **Signing & Capabilities** for each of the
   three targets.

5. Connect your iPhone via USB. Build & run on your device (▶︎ or ⌘R).

6. On first launch, sign in with your LibreLinkUp email and password.

### Personal Team vs paid Apple Developer

| | Free Personal Team | Paid Apple Developer Program |
|---|---|---|
| Cost | $0 | $99/yr |
| Build expiry on device | 7 days | 90 days (via TestFlight) |
| Re-install | Plug into Mac, hit run | Install once via TestFlight app |
| Devices | Your own iPhone + watch | Up to 100 internal testers |

## Acknowledgments

This wouldn't exist without the broader DIY diabetes community documenting
Abbott's APIs over the years. Particular thanks to the maintainers of the
various Nightscout, LibreLink-Up, and xDrip+ bridges that have kept the
information current. None of those projects were copied here — the Swift
code is original — but the protocol knowledge is theirs.

## License

[MIT](LICENSE) — do whatever you want with the code, but at your own risk
and without warranty.
