enum TaskRecurrence {
  none('Does not repeat'),
  daily('Daily'),
  weekdays('Weekdays'),
  weekly('Weekly');

  const TaskRecurrence(this.label);
  final String label;
}

/// A local task. Reminder and alarm instants are derived from one scheduled
/// date/time, so editing a task cannot leave stale native alarms behind.
class Task {
  const Task({
    required this.id,
    required this.title,
    required this.category,
    required this.priority,
    required this.date,
    required this.done,
    this.time,
    this.notes = '',
    this.recurrence = TaskRecurrence.none,
  });

  final String id;
  final String title;
  final String category;
  final String priority;
  final DateTime date;
  final bool done;
  final String? time;
  final String notes;
  final TaskRecurrence recurrence;

  DateTime? get scheduledDateTime {
    if (time == null) return null;
    final parts = time!.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return DateTime(date.year, date.month, date.day, hour, minute);
  }

  DateTime? get reminderDateTime =>
      scheduledDateTime?.subtract(const Duration(minutes: 5));
  DateTime? get alarmDateTime => scheduledDateTime;
  bool get completed => done;

  Task copyWith({
    String? id,
    String? title,
    String? category,
    String? priority,
    DateTime? date,
    bool? done,
    String? time,
    String? notes,
    TaskRecurrence? recurrence,
  }) =>
      Task(
        id: id ?? this.id,
        title: title ?? this.title,
        category: category ?? this.category,
        priority: priority ?? this.priority,
        date: date ?? this.date,
        done: done ?? this.done,
        time: time ?? this.time,
        notes: notes ?? this.notes,
        recurrence: recurrence ?? this.recurrence,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'category': category,
        'priority': priority,
        'date': date.toIso8601String(),
        'done': done,
        'time': time,
        'notes': notes,
        'recurrence': recurrence.name,
      };

  factory Task.fromJson(Map<String, dynamic> value) => Task(
        id: value['id'] as String,
        title: value['title'] as String,
        category: value['category'] as String? ?? 'Personal',
        priority: value['priority'] as String? ?? 'Medium',
        date: DateTime.parse(value['date'] as String),
        done: value['done'] == true,
        time: value['time'] as String?,
        notes: value['notes'] as String? ?? '',
        recurrence: TaskRecurrence.values.firstWhere(
          (item) => item.name == value['recurrence'],
          orElse: () => TaskRecurrence.none,
        ),
      );
}
