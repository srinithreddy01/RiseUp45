import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/task.dart';
import '../utils/date_time.dart';

/// Delivers task reminders through Android's native AlarmManager layer.
/// Android persists alarm records for reboot recovery; iOS receives the
/// supported local-notification fallback and is not presented as a Clock alarm.
class TaskNotificationService {
  TaskNotificationService._();
  static final instance = TaskNotificationService._();
  static const _native = MethodChannel('riseup45/alarm');
  static const _reminderChannelId = 'riseup_task_reminders';
  static const _alarmChannelId = 'riseup_task_alarms';
  static const _testNotificationId = 2147483000;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  bool get _android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> initialize() async {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    if (!kIsWeb) {
      try {
        final zone = await FlutterTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(zone.identifier));
      } catch (_) {}
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
      );
      _initialized = true;
    } catch (_) {}
  }

  Future<bool> requestNotificationPermission() async {
    await initialize();
    if (!_initialized) return false;
    if (kIsWeb) {
      final web = _plugin.resolvePlatformSpecificImplementation<
          WebFlutterLocalNotificationsPlugin>();
      return await web?.requestNotificationsPermission() ?? false;
    }
    if (_android) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestNotificationsPermission();
      return await android?.areNotificationsEnabled() ?? false;
    }
    final darwin = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    return await darwin?.requestPermissions(
            alert: true, badge: true, sound: true) ??
        false;
  }

  /// Checks AlarmManager.canScheduleExactAlarms(), rather than trusting only
  /// the manifest declaration, before and during every Android schedule.
  Future<bool> requestExactAlarmPermission() async {
    if (!_android) return false;
    return await _native.invokeMethod<bool>('requestExactAlarmPermission') ??
        false;
  }

  Future<void> openNotificationSettings() async {
    await initialize();
    try {
      await _plugin.openAppNotificationSettings();
    } catch (_) {}
  }

  Future<ReminderPermissionState> permissionState() async {
    await initialize();
    if (!_initialized) return const ReminderPermissionState.unavailable();
    if (!_android) {
      return const ReminderPermissionState(
          notificationsAllowed: true, exactAlarmsAllowed: false);
    }
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return ReminderPermissionState(
      notificationsAllowed: await android?.areNotificationsEnabled() ?? false,
      exactAlarmsAllowed:
          await _native.invokeMethod<bool>('canScheduleExactAlarms') ?? false,
    );
  }

  Future<ReminderScheduleResult> schedule(Task task) async {
    await initialize();
    if (task.done || task.time == null || kIsWeb) {
      await cancel(task.id);
      return const ReminderScheduleResult.notScheduled();
    }
    final scheduledAt = _nextOccurrence(task);
    if (scheduledAt == null) {
      await cancel(task.id);
      return const ReminderScheduleResult.pastDue();
    }
    final early = scheduledAt.subtract(const Duration(minutes: 5));
    final earlyScheduled = early.isAfter(tz.TZDateTime.now(tz.local));

    if (_android) {
      final exact = await _native.invokeMethod<bool>('schedule', {
            'id': task.id,
            'title': task.title,
            'reminderAt': early.millisecondsSinceEpoch,
            'alarmAt': scheduledAt.millisecondsSinceEpoch,
            'recurrence': task.recurrence.name,
          }) ??
          false;
      return ReminderScheduleResult.scheduled(
          exact: exact,
          scheduledAt: scheduledAt,
          earlyReminderScheduled: earlyScheduled);
    }

    // iOS can alert locally at task time but cannot promise Clock behaviour.
    if (earlyScheduled) {
      await _plugin.zonedSchedule(
        id: _earlyId(task.id),
        title: 'Upcoming Task',
        body: 'Your task "${task.title}" starts in 5 minutes.',
        scheduledDate: early,
        notificationDetails: _reminderDetails,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: task.id,
      );
    }
    await _plugin.zonedSchedule(
      id: _alarmId(task.id),
      title: 'TASK TIME',
      body: task.title,
      scheduledDate: scheduledAt,
      notificationDetails: _alarmDetails,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      payload: task.id,
    );
    return ReminderScheduleResult.scheduled(
        exact: false,
        scheduledAt: scheduledAt,
        earlyReminderScheduled: earlyScheduled);
  }

  Future<List<String>> consumeCompletedTaskIds() async {
    if (!_android) return const [];
    try {
      return await _native
              .invokeListMethod<String>('consumeCompletedTaskIds') ??
          const [];
    } catch (_) {
      return const [];
    }
  }

  Future<bool> showTestNotification() async {
    await initialize();
    if (!_initialized || kIsWeb) return false;
    if (!(await permissionState()).notificationsAllowed) return false;
    if (_android) return await _native.invokeMethod<bool>('showTest') ?? false;
    await _plugin.show(
      id: _testNotificationId,
      title: 'RiseUP reminders are ready',
      body: 'This is a test task-time alert.',
      notificationDetails: _alarmDetails,
    );
    return true;
  }

  Future<void> cancel(String taskId) async {
    if (_android) await _native.invokeMethod<void>('cancel', {'id': taskId});
    if (_initialized) {
      await _plugin.cancel(id: _earlyId(taskId));
      await _plugin.cancel(id: _alarmId(taskId));
    }
  }

  Future<void> cancelAll() async {
    if (_android) await _native.invokeMethod<void>('cancelAll');
    await initialize();
    if (_initialized) await _plugin.cancelAll();
  }

  Future<void> syncAll(Iterable<Task> tasks) async {
    for (final task in tasks) {
      await schedule(task);
    }
  }

  tz.TZDateTime? _nextOccurrence(Task task) {
    final scheduled = task.scheduledDateTime;
    if (scheduled == null) return null;
    final hour = scheduled.hour;
    final minute = scheduled.minute;
    var date = scheduled;
    var result =
        tz.TZDateTime(tz.local, date.year, date.month, date.day, hour, minute);
    while (!result.isAfter(tz.TZDateTime.now(tz.local))) {
      if (task.recurrence == TaskRecurrence.none) return null;
      date = nextOccurrence(date, task.recurrence);
      result = tz.TZDateTime(
          tz.local, date.year, date.month, date.day, hour, minute);
    }
    return result;
  }

  int _earlyId(String id) => (id.hashCode & 0x3fffffff) * 2;
  int _alarmId(String id) => _earlyId(id) + 1;
}

const _reminderDetails = NotificationDetails(
  android: AndroidNotificationDetails(
    TaskNotificationService._reminderChannelId,
    'Task reminders',
    channelDescription: 'Five-minute RiseUP task reminders',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
    playSound: true,
    enableVibration: true,
  ),
  iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
);

const _alarmDetails = NotificationDetails(
  android: AndroidNotificationDetails(
    TaskNotificationService._alarmChannelId,
    'Task alarms',
    channelDescription: 'RiseUP task-time alarms',
    importance: Importance.max,
    priority: Priority.max,
    playSound: true,
    enableVibration: true,
    audioAttributesUsage: AudioAttributesUsage.alarm,
    category: AndroidNotificationCategory.alarm,
    visibility: NotificationVisibility.public,
  ),
  iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
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
