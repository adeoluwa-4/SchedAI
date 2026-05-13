# SchedAI

SchedAI is an iPhone app that helps you turn messy plans into a real schedule.

Type or say what you need to do, and SchedAI helps break it into tasks, place it on your day, and keep you moving.

## What It Does

- Adds tasks from plain language, like "study for 2 hours tomorrow" or "finish essay tonight"
- Plans your day around a work window, like 9 AM to 5 PM
- Keeps fixed-time tasks in place
- Sorts flexible tasks by priority and time needed
- Shows today's schedule in a simple timeline
- Supports reminders before tasks start
- Can sync planned tasks to Apple Calendar
- Includes a home screen widget for quick access

## Why I Built It

Most planning apps make you do all the organizing yourself.

SchedAI is meant to feel more like a small planning assistant: you give it the rough version of your day, and it helps turn that into something you can actually follow.

## Screenshots

The project includes screenshots in `site/media/`.

- `todayview.png`
- `widget-overview.png`
- `settings-overview.png`

## Running The App

1. Open `SchedAI.xcodeproj` in Xcode.
2. Select the `SchedAI` scheme.
3. Choose an iPhone simulator or your device.
4. Press Run.

The app works without the online AI parser. It has an offline parser built in, so basic task planning still works even if the API is not set up.

## Optional AI Setup

SchedAI can use a small Vercel API route to improve task parsing with OpenAI.

The API lives here:

```text
api/parse-tasks.js
```

To use it, set an `OPENAI_API_KEY` in your Vercel project. The iOS app points to the deployed parser endpoint by default, and falls back to offline parsing if the API is unavailable.

Recommended abuse controls for the hosted parser:

- Keep the OpenAI key only in Vercel server env vars. The iOS app never calls OpenAI directly.
- Set `SCHEDAI_RATE_LIMIT_REQUESTS=5` and `SCHEDAI_RATE_LIMIT_WINDOW_MS=60000` for a five-requests-per-minute default.
- Set `SCHEDAI_AI_ENABLED=true` so you can flip it to `false` as a global kill switch without shipping an app update.
- Set `SCHEDAI_BLOCKED_CLIENT_IDS=` with a comma-separated list of client IDs to disable AI for specific abusive installs.
- Set `SCHEDAI_REQUIRE_CLIENT_ID=true` after your current app builds are sending `X-SchedAI-Client-ID` to the API.

## Tech Used

- SwiftUI for the iOS app
- WidgetKit for the widget
- EventKit for Apple Calendar support
- UserNotifications for reminders
- Node.js / Vercel for the optional AI parser

## Status

SchedAI is still growing, but the core idea is already here: add tasks quickly, plan your day, and spend less time dragging things around manually.
