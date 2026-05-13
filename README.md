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

## Tech Used

- SwiftUI for the iOS app
- WidgetKit for the widget
- EventKit for Apple Calendar support
- UserNotifications for reminders
- Node.js / Vercel for the optional AI parser

## Status

SchedAI is still growing, but the core idea is already here: add tasks quickly, plan your day, and spend less time dragging things around manually.
