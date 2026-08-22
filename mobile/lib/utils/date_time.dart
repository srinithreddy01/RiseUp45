import '../models/task.dart';

DateTime nextOccurrence(DateTime date, TaskRecurrence recurrence) {
  switch (recurrence) {
    case TaskRecurrence.daily:
      return DateTime(date.year, date.month, date.day + 1);
    case TaskRecurrence.weekdays:
      var next = DateTime(date.year, date.month, date.day + 1);
      while (next.weekday == DateTime.saturday ||
          next.weekday == DateTime.sunday) {
        next = next.add(const Duration(days: 1));
      }
      return next;
    case TaskRecurrence.weekly:
      return DateTime(date.year, date.month, date.day + 7);
    case TaskRecurrence.none:
      return date;
  }
}
