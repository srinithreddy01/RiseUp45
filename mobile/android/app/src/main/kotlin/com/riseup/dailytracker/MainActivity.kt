package com.riseup.dailytracker

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
  override fun configureFlutterEngine(engine: FlutterEngine) {
    super.configureFlutterEngine(engine)
    MethodChannel(engine.dartExecutor.binaryMessenger, "riseup45/alarm")
      .setMethodCallHandler { call, result ->
        when (call.method) {
          "canScheduleExactAlarms" -> result.success(RiseUpAlarmScheduler.exact(this))
          "requestExactAlarmPermission" -> result.success(RiseUpAlarmScheduler.requestExact(this))
          "schedule" -> {
            val id = call.argument<String>("id")
            val title = call.argument<String>("title")
            val reminderAt = call.argument<Long>("reminderAt")
            val alarmAt = call.argument<Long>("alarmAt")
            val recurrence = call.argument<String>("recurrence") ?: "none"
            if (id == null || title == null || reminderAt == null || alarmAt == null) result.error("invalid_task", "Missing task alarm fields", null)
            else result.success(RiseUpAlarmScheduler.schedule(this, RiseUpAlarm(id, title, reminderAt, alarmAt, recurrence)))
          }
          "cancel" -> { call.argument<String>("id")?.let { RiseUpAlarmScheduler.cancel(this, it) }; result.success(null) }
          "cancelAll" -> { RiseUpAlarmScheduler.cancelAll(this); result.success(null) }
          "consumeCompletedTaskIds" -> result.success(RiseUpAlarmScheduler.consumeDone(this))
          "showTest" -> { RiseUpNotifications.reminder(this, "riseup-test", "RiseUP reminders are ready", "This is a test alert. Check sound and vibration."); result.success(true) }
          else -> result.notImplemented()
        }
      }
  }
}
