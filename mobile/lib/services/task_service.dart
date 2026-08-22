import '../models/task.dart';
import 'alarm_service.dart';

/// Coordinates a task mutation with its native reminder lifecycle.
class TaskService {
  const TaskService(this._alarms);
  final AlarmService _alarms;

  Future<ReminderScheduleResult> save(Task task) => _alarms.schedule(task);
  Future<void> delete(String taskId) => _alarms.cancel(taskId);
}
