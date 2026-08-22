# RiseUP45 architecture

```text
riseup45/
├── frontend/                 # Vite / React client
│   └── src/
│       ├── components/       # TaskCard, TaskForm, AlarmCard, NotificationCard, ProgressCard
│       ├── pages/            # Home, Tasks, Progress, Profile, Settings
│       ├── services/         # authService, taskService, databaseService
│       └── utils/            # date/time and task helpers
├── mobile/                   # Flutter application
│   ├── android/              # AlarmManager receiver and foreground alarm service
│   ├── ios/                  # Xcode runner / local notification support
│   ├── lib/
│   │   ├── models/task.dart
│   │   ├── screens/
│   │   ├── widgets/
│   │   ├── services/
│   │   │   ├── alarm_service.dart
│   │   │   ├── notification_service.dart
│   │   │   ├── task_service.dart
│   │   │   └── auth_service.dart
│   │   ├── database/
│   │   └── main.dart
│   └── pubspec.yaml
└── backend/                  # future sync boundary
    ├── api/
    ├── authentication/
    └── database/
```

## Task and reminder lifecycle

A task has one source of truth: `scheduledDateTime`. Its derived fields are:

```text
Task
├── id
├── title
├── scheduledDateTime
├── reminderDateTime = scheduledDateTime − 5 minutes
├── alarmDateTime = scheduledDateTime
└── completed
```

Saving a timed task cancels any prior intents for that task ID, persists the
new native alarm record, and schedules both events. Editing, completing, or
deleting a task cancels the previous events. Recurring tasks calculate and
schedule their next occurrence after firing. Boot, app replacement, and exact
alarm permission changes restore surviving future alarms.

| When | User experience | Implementation |
| --- | --- | --- |
| Task time − 5 min | `Upcoming Task`: “Your task … starts in 5 minutes.” | Separate default-importance notification channel |
| Task time | `TASK TIME` with DONE and SNOOZE | Alarm channel, alarm audio, vibration, public lock-screen notification, and foreground alarm service |

## Android requirements

The app declares notification, vibration, boot, exact-alarm, full-screen
intent, and foreground media-playback permissions. Before each native schedule
it checks `AlarmManager.canScheduleExactAlarms()`. When allowed it uses
`setExactAndAllowWhileIdle()`; otherwise it uses Android's inexact
idle-safe fallback and tells the user to enable **Alarms & reminders**.

On Android 13+, users must allow notifications. On Android 14+, the app checks
whether full-screen intent is allowed and only uses it for the task alarm. Test
on a physical phone: notification permission, exact alarm permission, lock
screen, Doze, device reboot, edits/deletes, DONE, SNOOZE, and recurring tasks.

## iOS behaviour

iOS receives a five-minute local notification and a task-time, high-priority
local notification with sound. It must be tested on real iPhones after signing
in Xcode. RiseUP does not claim Clock-style continuously ringing behaviour on
iOS, because third-party iOS apps cannot guarantee it.

## Run

```powershell
npm --prefix frontend run dev
cd mobile
..\.flutter-sdk\bin\flutter.bat pub get
..\.flutter-sdk\bin\flutter.bat run
```