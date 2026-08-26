# SchedAI

SchedAI is a native iPhone planner that turns rough, natural language tasks into a realistic daily schedule. It combines fast capture, deterministic offline parsing, calendar awareness, reminders, and a home screen widget in a focused SwiftUI experience.

[View SchedAI on the App Store](https://apps.apple.com/us/app/schedai/id6777319679) · [Visit the product site](https://schedai-snowy.vercel.app)

![SchedAI Today view](site/media/todayview.png)

## Product highlights

- Capture tasks by typing or speaking phrases such as "study for two hours tomorrow."
- Extract dates, times, durations, and task titles with the on device parser.
- Build a schedule around work hours, fixed tasks, priorities, and busy calendar periods.
- Review the day in a native timeline and edit tasks before committing changes.
- Schedule local reminders and optionally add planned work to Apple Calendar.
- Keep the next tasks visible through WidgetKit.
- Use the core planner without a network connection or hosted AI credentials.
- Upgrade to SchedAI Pro for expanded hosted AI access and an ad-free experience.

## How it works

```mermaid
flowchart LR
    A["Typed or spoken plan"] --> B["OfflineNLP / OnDeviceTaskParser"]
    A --> C["Optional hosted AI parser"]
    B --> D["TaskItem drafts"]
    C --> D
    D --> E["Scheduler"]
    F["Work window and calendar events"] --> E
    E --> G["Today timeline"]
    G --> H["Reminders, Calendar, and WidgetKit"]
```

`AppState` coordinates persistence and planning. `OfflineNLP` and `OnDeviceTaskParser` provide the local parsing path, while `AIService` can request richer parsing from the optional Vercel endpoint. `Scheduler` places tasks into available time, and the calendar, notification, and widget layers expose the resulting plan across iOS.

## Screenshots

| Today | Widget | Settings |
| --- | --- | --- |
| ![Today timeline](site/media/todayview.png) | ![SchedAI widget](site/media/widget-overview.png) | ![Settings](site/media/settings-overview.png) |

## Technology

- SwiftUI and Swift Concurrency
- StoreKit 2 subscriptions and server-verified transaction entitlements
- WidgetKit and App Intents
- EventKit and UserNotifications
- Speech framework integration
- Local persistence and shared app group data
- Node.js and Vercel for the optional hosted parser

## Run locally

Requirements: Xcode with an iOS 17 or newer simulator, or an iPhone running iOS 17 or newer.

1. Clone the repository.
2. Open `SchedAI.xcodeproj`.
3. Select the `SchedAI` scheme and a development team if device signing is required.
4. Choose a simulator or connected iPhone.
5. Build and run.

No hosted AI configuration is required for the offline planning flow. Calendar, notifications, speech recognition, and widgets require their corresponding system permissions.

### Test SchedAI Pro locally

The shared `SchedAI` scheme uses `SchedAI/Products.storekit` with the same product identifiers expected in App Store Connect:

- `me.SchedAI.pro.monthly`
- `me.SchedAI.pro.annual`

Run the app from Xcode and purchase either test product to exercise the paywall, entitlement refresh, purchase restoration, ad removal, and Pro Settings state. Xcode StoreKit transactions validate inside the app, but they are signed by the local StoreKit certificate. Use an App Store Sandbox or TestFlight purchase to test server-side hosted-AI entitlement verification.

### Configure production subscriptions

Create one `SchedAI Pro` subscription group in App Store Connect and add the monthly and annual product identifiers above. Complete pricing, localization, review screenshots, availability, and any introductory offer in App Store Connect before submitting the first subscriptions with a new app version.

The optional hosted parser verifies a subscriber's signed StoreKit transaction with Apple's official App Store Server library. Its deployment requires:

- `OPENAI_API_KEY`
- `APPLE_ROOT_CA_BASE64S`: comma- or newline-separated base64 DER Apple root certificates from the Apple PKI page
- `APPLE_BUNDLE_ID` (defaults to `me.SchedAI`)
- `APPLE_APP_ID` (defaults to `6777319679`)
- `APPLE_PRO_PRODUCT_IDS` (defaults to the monthly and annual identifiers above)

Free users receive three hosted AI improvements per UTC day by default. Override that allowance with `AI_FREE_DAILY_REQUESTS`. Existing per-client, IP, and global rate limits still apply to Pro requests as fair-use protection.

## Verification

- Unit and UI test targets are included in `SchedAITests/` and `SchedAIUITests/`.
- Monetization tests cover product identifiers and daily hosted-AI allowance behavior.
- Backend tests cover active, expired, revoked, unrelated, and wrong-bundle subscription transactions.
- A deterministic parser harness is available in `Tools/NLPTestRunner.swift`.
- Privacy manifests are included for the app and widget targets.

## Privacy

Planning works locally by default. SchedAI requests calendar, reminder, speech, or hosted AI access only for the features the user chooses to enable. The optional hosted parser is separated from the on device parser so the main task planning workflow remains available offline.
