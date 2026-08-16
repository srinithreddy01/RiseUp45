import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'main.dart';

/// Schedules the device notifications used for task reminders.
///
/// Android owns delivery once a reminder is scheduled, so reminders continue
/// when RiseUP is closed. Exact alarm access is optional: without it, Android
/// still delivers an inexact reminder while the device is idle.
class TaskNotificationService {
  TaskNotificationService._();

  static final instance = TaskNotificationService._();
  static const _reminderChannelId = 'riseup_task_reminders';
  static const _reminderChannelName = 'Task reminders';
  static const _alarmChannelId = 'riseup_task_alarms';
  static const _alarmChannelName = 'Task alarms';
  static const _channelDescription = 'Alerts for scheduled RiseUP tasks';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  static const _testNotificationId = 2147483000;

  Future<void> initialize() async {
    if (_initialized) return;

    tz_data.initializeTimeZones();
    if (!kIsWeb) {
      try {
        final deviceZone = await FlutterTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(deviceZone.identifier));
      } catch (_) {
        // UTC is a safe fallback in environments without a platform channel.
      }
    }

    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('ic_notification'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: (response) {},
      );
      _initialized = true;
    } catch (_) {
      // Widget tests and unsupported platforms do not supply a notification
      // channel. The app remains usable there without scheduled reminders.
    }
  }

  /// Requests the notification runtime permission. Call from a user action.
  Future<bool> requestNotificationPermission() async {
    await initialize();
    if (!_initialized) return false;

    if (kIsWeb) {
      final web = _plugin.resolvePlatformSpecificImplementation<
          WebFlutterLocalNotificationsPlugin>();
      return await web?.requestNotificationsPermission() ?? false;
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestNotificationsPermission();
      return await android?.areNotificationsEnabled() ?? false;
    }
    return true;
  }

  /// Opens Android's special-access page for precise alarm delivery.
  Future<bool> requestExactAlarmPermission() async {
    await initialize();
    if (!_initialized ||
        kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    var granted = await android?.canScheduleExactNotifications() == true;
    if (!granted) {
      await android?.requestExactAlarmsPermission();
      granted = await android?.canScheduleExactNotifications() == true;
    }
    return granted;
  }

  Future<void> openNotificationSettings() async {
    await initialize();
    if (!_initialized || kIsWeb) return;
    try {
      await _plugin.openAppNotificationSettings();
    } catch (_) {
      // The settings screen is not available on every test/desktop platform.
    }
  }

  /// The current Android permission state, used to give the user a clear
  /// explanation instead of silently failing to alert them.
  Future<ReminderPermissionState> permissionState() async {
    await initialize();
    if (!_initialized) return const ReminderPermissionState.unavailable();
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return const ReminderPermissionState(
          notificationsAllowed: true, exactAlarmsAllowed: false);
    }
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return ReminderPermissionState(
      notificationsAllowed: await android?.areNotificationsEnabled() ?? false,
      exactAlarmsAllowed:
          await android?.canScheduleExactNotifications() ?? false,
    );
  }

  Future<ReminderScheduleResult> schedule(Task task) async {
    await initialize();
    if (!_initialized || task.done || task.time == null || kIsWeb) {
      await cancel(task.id);
      return const ReminderScheduleResult.notScheduled();
    }

    final pieces = task.time!.split(':');
    if (pieces.length != 2) return const ReminderScheduleResult.notScheduled();
    final hour = int.tryParse(pieces[0]);
    final minute = int.tryParse(pieces[1]);
    if (hour == null || minute == null) {
      return const ReminderScheduleResult.notScheduled();
    }

    final scheduledAt = tz.TZDateTime(
      tz.local,
      task.date.year,
      task.date.month,
      task.date.day,
      hour,
      minute,
    );
    if (!scheduledAt.isAfter(tz.TZDateTime.now(tz.local))) {
      await cancel(task.id);
      return const ReminderScheduleResult.pastDue();
    }

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final exactAllowed = await android?.canScheduleExactNotifications() == true;
    final scheduleMode = exactAllowed
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;
    final reminderAt = scheduledAt.subtract(const Duration(minutes: 5));

    // The early notification is intentionally a separate alarm. This makes it
    // reliable even after the app is closed and lets users distinguish the
    // five-minute heads-up from the actual task-time alarm.
    final earlyReminderScheduled = reminderAt.isAfter(tz.TZDateTime.now(tz.local));
    if (earlyReminderScheduled) {
      await _plugin.zonedSchedule(
        id: _earlyReminderNotificationId(task.id),
        title: 'Task in 5 minutes',
        body: '${task.title} starts at ${task.time}.',
        scheduledDate: reminderAt,
        notificationDetails: _reminderNotificationDetails,
        androidScheduleMode: scheduleMode,
        payload: task.id,
      );
    }

    await _plugin.zonedSchedule(
      id: _taskTimeAlarmNotificationId(task.id),
      title: 'Time for ${task.title}',
      body: 'Your task is due now.',
      scheduledDate: scheduledAt,
      notificationDetails: _alarmNotificationDetails,
      androidScheduleMode: scheduleMode,
      payload: task.id,
    );
    return ReminderScheduleResult.scheduled(
      exact: exactAllowed,
      scheduledAt: scheduledAt,
      earlyReminderScheduled: earlyReminderScheduled,
    );
  }

  /// Sends an immediate notification so a user can confirm the channel's
  /// sound and alert settings on this specific device.
  Future<bool> showTestNotification() async {
    await initialize();
    if (!_initialized || kIsWeb) return false;
    final state = await permissionState();
    if (!state.notificationsAllowed) return false;
    await _plugin.show(
      id: _testNotificationId,
      title: 'RiseUP reminders are ready',
      body: 'This is a test alert. Your scheduled task reminders will use this sound.',
      notificationDetails: _alarmNotificationDetails,
    );
    return true;
  }

  Future<void> cancel(String taskId) async {
    if (!_initialized) return;
    await _plugin.cancel(id: _earlyReminderNotificationId(taskId));
    await _plugin.cancel(id: _taskTimeAlarmNotificationId(taskId));
  }

  Future<void> cancelAll() async {
    await initialize();
    if (_initialized) await _plugin.cancelAll();
  }

  Future<void> syncAll(Iterable<Task> tasks) async {
    for (final task in tasks) {
      await schedule(task);
    }
  }

  int _earlyReminderNotificationId(String taskId) =>
      (taskId.hashCode & 0x3fffffff) * 2;

  int _taskTimeAlarmNotificationId(String taskId) =>
      _earlyReminderNotificationId(taskId) + 1;
}

const _reminderNotificationDetails = NotificationDetails(
  android: AndroidNotificationDetails(
    TaskNotificationService._reminderChannelId,
    TaskNotificationService._reminderChannelName,
    channelDescription: TaskNotificationService._channelDescription,
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
    playSound: true,
    enableVibration: true,
  ),
);

const _alarmNotificationDetails = NotificationDetails(
  android: AndroidNotificationDetails(
    TaskNotificationService._alarmChannelId,
    TaskNotificationService._alarmChannelName,
    channelDescription: TaskNotificationService._channelDescription,
    importance: Importance.max,
    priority: Priority.max,
    playSound: true,
    enableVibration: true,
    audioAttributesUsage: AudioAttributesUsage.alarm,
  ),
);

class ReminderPermissionState {
  const ReminderPermissionState({
    required this.notificationsAllowed,
    required this.exactAlarmsAllowed,
  });
  const ReminderPermissionState.unavailable()
      : notificationsAllowed = false,
        exactAlarmsAllowed = false;

  final bool notificationsAllowed;
  final bool exactAlarmsAllowed;
}

class ReminderScheduleResult {
  const ReminderScheduleResult._({
    required this.scheduled,
    required this.exact,
    this.scheduledAt,
    this.earlyReminderScheduled = false,
    this.wasPastDue = false,
  });
  const ReminderScheduleResult.notScheduled()
      : this._(scheduled: false, exact: false);
  const ReminderScheduleResult.pastDue()
      : this._(scheduled: false, exact: false, wasPastDue: true);
  ReminderScheduleResult.scheduled({
    required bool exact,
    required tz.TZDateTime scheduledAt,
    required bool earlyReminderScheduled,
  }) : this._(
          scheduled: true,
          exact: exact,
          scheduledAt: scheduledAt,
          earlyReminderScheduled: earlyReminderScheduled,
        );

  final bool scheduled;
  final bool exact;
  final tz.TZDateTime? scheduledAt;
  final bool earlyReminderScheduled;
  final bool wasPastDue;
}
