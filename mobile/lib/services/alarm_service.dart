import '../models/task.dart';
import 'notification_service.dart';

export 'notification_service.dart'
    show ReminderPermissionState, ReminderScheduleResult;

/// The scheduling boundary used by task screens.
///
/// On Android it delegates to the native AlarmManager scheduler; on iOS it
/// uses the supported local-notification implementation.
class AlarmService {
  AlarmService._();
  static final instance = AlarmService._();

  Future<ReminderScheduleResult> schedule(Task task) =>
      TaskNotificationService.instance.schedule(task);
  Future<void> cancel(String taskId) =>
      TaskNotificationService.instance.cancel(taskId);
  Future<void> cancelAll() => TaskNotificationService.instance.cancelAll();
  Future<void> syncAll(Iterable<Task> tasks) =>
      TaskNotificationService.instance.syncAll(tasks);
  Future<ReminderPermissionState> permissionState() =>
      TaskNotificationService.instance.permissionState();
  Future<bool> requestNotificationPermission() =>
      TaskNotificationService.instance.requestNotificationPermission();
  Future<bool> requestExactAlarmPermission() =>
      TaskNotificationService.instance.requestExactAlarmPermission();
  Future<void> openNotificationSettings() =>
      TaskNotificationService.instance.openNotificationSettings();
  Future<List<String>> consumeCompletedTaskIds() =>
      TaskNotificationService.instance.consumeCompletedTaskIds();
  Future<bool> showTestNotification() =>
      TaskNotificationService.instance.showTestNotification();
}
